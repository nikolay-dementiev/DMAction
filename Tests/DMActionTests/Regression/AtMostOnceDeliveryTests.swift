import DMAction
import XCTest

/// A producer that completed more than once used to continue its run once per completion:
/// the rest of the chain ran again and the consumer was called again. Now the first
/// completion of an attempt wins and the consumer is called at most once per run. A producer
/// that never completes still stalls its run: this is at most once, not a promise of an answer.
final class AtMostOnceDeliveryTests: XCTestCase {
    /// A third-party action whose own closure completes twice.
    private struct TwiceCompletingAction: DMAction {
        let currentAttempt: UInt = 0
        let id = UUID()
        let action: ActionType = { completion in
            completion(.success("first"))
            completion(.success("second"))
        }
    }

    // MARK: - Two completions before the call returns

    func test_run_whenAProducerSucceedsTwice_deliversTheFirstSuccessOnce() {
        let consumer = ConsumerSpy()
        let action = DMButtonAction { completion in
            completion(.success("first"))
            completion(.success("second"))
        }

        action.action(consumer.receive)

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "first", "the first completion wins")
    }

    func test_fallbackTo_whenThePrimaryFailsThenSucceeds_deliversOnlyTheFallbacksResult() {
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
            completion(.success("late"))
        }

        primary.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(fallback.callCount, 1, "the fallback runs once")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "fallback", "the late success is ignored")
    }

    func test_fallbackTo_whenThePrimarySucceedsThenFails_deliversOnlyTheSuccess() {
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()
        let primary = DMButtonAction { completion in
            completion(.success("primary"))
            completion(.failure(MarkedError()))
        }

        primary.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(fallback.callCount, 0, "the late failure starts no fallback")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "primary", "the first completion wins")
    }

    func test_run_whenAKeptResultIsFollowedByACompletionFromAnotherThread_ignoresTheSecond() {
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()
        var secondCompletion: DispatchTimeoutResult?
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
            let finished = DispatchSemaphore(value: 0)
            BackgroundCaller {
                completion(.success("late"))
                finished.signal()
            }
            .start()
            secondCompletion = finished.wait(timeout: .now() + 5)
        }

        primary.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(secondCompletion, .success, "the second completion returned before the call did")
        XCTAssertEqual(fallback.callCount, 1, "the fallback runs once, after the first completion")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "fallback", "the late success is ignored")
    }

    // MARK: - Completions after the attempt moved on

    func test_run_whenACompletionArrivesAfterTheNextAttemptStarted_ignoresIt() throws {
        let primary = ProducerSpy("primary", script: [.hold])
        let fallback = ProducerSpy("fallback", script: [.hold])
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).action(consumer.receive)
        let primaryCompletion = try XCTUnwrap(primary.heldCompletions.first, "the primary kept its completion")
        primaryCompletion(.failure(MarkedError()))
        let fallbackCompletion = try XCTUnwrap(fallback.heldCompletions.first, "the fallback kept its completion")
        primaryCompletion(.success("late"))
        let deliveriesAfterTheLateCompletion = consumer.count
        fallbackCompletion(.success("fallback"))

        XCTAssertEqual(deliveriesAfterTheLateCompletion, 0, "the late completion of the primary delivers nothing")
        XCTAssertEqual(primary.callCount + fallback.callCount, 2, "nothing runs again")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "fallback", "the fallback's result")
    }

    func test_run_whenACompletionArrivesAfterTheRunFinished_ignoresIt() throws {
        let producer = ProducerSpy(script: [.hold])
        let consumer = ConsumerSpy()

        producer.action.retry(1).action(consumer.receive)
        let completion = try XCTUnwrap(producer.heldCompletions.first, "the producer kept its completion")
        completion(.success("first"))
        completion(.success("again"))
        completion(.failure(MarkedError()))

        XCTAssertEqual(producer.callCount, 1, "a late failure starts no retry")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "first", "the first completion wins")
    }

    // MARK: - Lifetime

    func test_run_afterDelivery_releasesTheConsumerWhileAProducerKeepsItsCompletion() {
        final class Token {}
        weak var weakToken: Token?
        var kept: ((DMButtonAction.ResultType) -> Void)?
        do {
            let token = Token()
            weakToken = token
            let action = DMButtonAction { completion in
                kept = completion
                completion(.success("value"))
            }
            action.action { _ in
                _ = token
            }
        }

        XCTAssertNotNil(kept, "the producer still holds its completion")
        XCTAssertNil(weakToken, "what the consumer captured is released after the delivery")
    }

    // MARK: - Call syntax on a third-party action

    func test_callSyntax_onACustomActionThatCompletesTwice_deliversOnce() {
        let consumer = ConsumerSpy()
        let action = TwiceCompletingAction()

        action(completion: consumer.receive)

        XCTAssertEqual(consumer.count, 1, "call syntax delivers once")
        XCTAssertEqual(consumer.lastValue, "first", "the first completion wins")
        XCTAssertEqual(consumer.lastLabel, 0, "labelled with the action's attempt")
    }

    // MARK: - Many threads: exact counts first, then the Thread Sanitizer

    func test_run_whenManyThreadsCompleteOneAttempt_runsTheFallbackAndDeliversOncePerRun() {
        let runs = 50
        let threadsPerRun = 4
        let fallbackCalls = LockedCounter()
        let deliveries = LockedCounter()
        let completions = DispatchGroup()
        let fallback = DMButtonAction { completion in
            fallbackCalls.increment()
            completion(.success("fallback"))
        }
        let primary = DMButtonAction { completion in
            for _ in 0..<threadsPerRun {
                completions.enter()
                BackgroundCaller {
                    completion(.failure(MarkedError()))
                    completions.leave()
                }
                .start()
            }
        }
        let action = primary.fallbackTo(fallback)

        for _ in 0..<runs {
            action.action { _ in
                deliveries.increment()
            }
        }

        XCTAssertEqual(completions.wait(timeout: .now() + 10), .success, "every completion call returned")
        XCTAssertEqual(fallbackCalls.count, runs, "one fallback per run")
        XCTAssertEqual(deliveries.count, runs, "one delivery per run")
    }
}
