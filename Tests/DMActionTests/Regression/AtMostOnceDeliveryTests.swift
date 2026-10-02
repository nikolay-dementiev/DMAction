import DMAction
import OSLog
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

    private struct SUT {
        let producer: ProducerSpy
        let fallback: ProducerSpy
        let consumer = ConsumerSpy()
    }

    // MARK: - Two completions before the call returns

    func test_run_whenAProducerSucceedsTwice_deliversTheFirstSuccessOnce() {
        let sut = makeSUT()
        let action = DMButtonAction { completion in
            completion(.success("first"))
            completion(.success("second"))
        }

        action.action(sut.consumer.receive)

        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
    }

    func test_fallbackTo_whenThePrimaryFailsThenSucceeds_deliversOnlyTheFallbacksResult() {
        let sut = makeSUT()
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
            completion(.success("late"))
        }

        primary.fallbackTo(sut.fallback.action).action(sut.consumer.receive)

        XCTAssertEqual(sut.fallback.callCount, 1, "the fallback runs once")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the late success is ignored")
    }

    func test_fallbackTo_whenThePrimarySucceedsThenFails_deliversOnlyTheSuccess() {
        let sut = makeSUT()
        let primary = DMButtonAction { completion in
            completion(.success("primary"))
            completion(.failure(MarkedError()))
        }

        primary.fallbackTo(sut.fallback.action).action(sut.consumer.receive)

        XCTAssertEqual(sut.fallback.callCount, 0, "the late failure starts no fallback")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "primary", "the first completion wins")
    }

    func test_run_whenAKeptResultIsFollowedByACompletionFromAnotherThread_ignoresTheSecond() {
        let sut = makeSUT()
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

        primary.fallbackTo(sut.fallback.action).action(sut.consumer.receive)

        XCTAssertEqual(secondCompletion, .success, "the second completion returned before the call did")
        XCTAssertEqual(sut.fallback.callCount, 1, "the fallback runs once, after the first completion")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the late success is ignored")
    }

    // MARK: - Completions after the attempt moved on

    func test_run_whenACompletionArrivesAfterTheNextAttemptStarted_ignoresIt() throws {
        let sut = makeSUT(producer: [.hold], fallback: [.hold])

        sut.producer.action.fallbackTo(sut.fallback.action).action(sut.consumer.receive)
        let primaryCompletion = try XCTUnwrap(sut.producer.heldCompletions.first, "the primary kept its completion")
        primaryCompletion(.failure(MarkedError()))
        let fallbackCompletion = try XCTUnwrap(sut.fallback.heldCompletions.first, "the fallback kept its completion")
        primaryCompletion(.success("late"))
        let deliveriesAfterTheLateCompletion = sut.consumer.count
        fallbackCompletion(.success("fallback"))

        XCTAssertEqual(deliveriesAfterTheLateCompletion, 0, "the late completion of the primary delivers nothing")
        XCTAssertEqual(sut.producer.callCount + sut.fallback.callCount, 2, "nothing runs again")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the fallback's result")
    }

    func test_run_whenACompletionArrivesAfterTheRunFinished_ignoresIt() throws {
        let sut = makeSUT(producer: [.hold])

        sut.producer.action.retry(1).action(sut.consumer.receive)
        let completion = try XCTUnwrap(sut.producer.heldCompletions.first, "the producer kept its completion")
        completion(.success("first"))
        completion(.success("again"))
        completion(.failure(MarkedError()))

        XCTAssertEqual(sut.producer.callCount, 1, "a late failure starts no retry")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
    }

    func test_run_whenTheConsumerWaitsForALateCompletionFromAnotherThread_doesNotHoldItUp() throws {
        let sut = makeSUT(producer: [.hold])
        var lateCompletion: DispatchTimeoutResult?
        sut.producer.action.action { result in
            sut.consumer.receive(result)
            guard let held = sut.producer.heldCompletions.first else {
                return
            }
            let returned = DispatchSemaphore(value: 0)
            BackgroundCaller {
                held(.failure(MarkedError()))
                returned.signal()
            }
            .start()
            lateCompletion = returned.wait(timeout: .now() + 2)
        }
        let completion = try XCTUnwrap(sut.producer.heldCompletions.first, "the producer kept its completion")

        completion(.success("first"))

        XCTAssertEqual(lateCompletion, .success, "the run holds no lock while the consumer runs")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
    }

    func test_run_whenACompletionIsIgnored_writesAFaultToTheUnifiedLog() throws {
        guard #available(macOS 12, iOS 15, watchOS 8, tvOS 15, *) else {
            throw XCTSkip("Reading the log of this process needs OSLogStore")
        }
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let start = store.position(date: Date())
        let action = DMButtonAction { completion in
            completion(.success("first"))
            completion(.success("second"))
        }

        action.action { _ in }

        let entries = try store.getEntries(at: start, matching: NSPredicate(format: "subsystem == %@", "DMAction"))
        let faults = entries.compactMap { $0 as? OSLogEntryLog }.filter { $0.level == .fault }
        XCTAssertTrue(faults.contains { $0.composedMessage.contains("completed more than once") })
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

    func test_run_afterTheFirstCompletion_releasesWhatTheProducerCapturedWhileItKeepsItsCompletion() {
        final class Token {}
        weak var weakToken: Token?
        var kept: ((DMButtonAction.ResultType) -> Void)?
        do {
            let token = Token()
            weakToken = token
            let action = DMButtonAction { completion in
                _ = token
                kept = completion
                completion(.success("value"))
            }
            action.action { _ in }
        }

        XCTAssertNotNil(kept, "the producer still holds its completion")
        XCTAssertNil(weakToken, "the plan, and the producer in it, are released with the action")
    }

    // MARK: - Call syntax on a third-party action

    func test_callSyntax_onACustomActionThatCompletesTwice_deliversOnce() {
        let sut = makeSUT()
        let action = TwiceCompletingAction()

        action(completion: sut.consumer.receive)

        XCTAssertEqual(sut.consumer.count, 1, "call syntax delivers once")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
        XCTAssertEqual(sut.consumer.lastLabel, 0, "labelled with the action's attempt")
    }

    // MARK: - Many threads: exact counts first, then the Thread Sanitizer

    func test_run_whenManyThreadsCompleteOneAttemptTogether_runsTheFallbackAndDeliversOncePerRun() {
        let runs = 500
        let threadsPerRun = 4
        let fallbackCalls = LockedCounter()
        let deliveries = LockedCounter()
        let completions = DispatchGroup()
        let fallback = DMButtonAction { completion in
            fallbackCalls.increment()
            completion(.success("fallback"))
        }
        let primary = DMButtonAction { completion in
            // The threads wait at a gate until all of them exist, then complete together.
            let ready = DispatchGroup()
            let gate = DispatchSemaphore(value: 0)
            for _ in 0..<threadsPerRun {
                completions.enter()
                ready.enter()
                BackgroundCaller {
                    ready.leave()
                    _ = gate.wait(timeout: .now() + 5)
                    completion(.failure(MarkedError()))
                    completions.leave()
                }
                .start()
            }
            _ = ready.wait(timeout: .now() + 5)
            for _ in 0..<threadsPerRun {
                gate.signal()
            }
        }
        let action = primary.fallbackTo(fallback)

        for _ in 0..<runs {
            action.action { _ in
                deliveries.increment()
            }
        }

        XCTAssertEqual(completions.wait(timeout: .now() + 60), .success, "every completion call returned")
        XCTAssertEqual(fallbackCalls.count, runs, "one fallback per run")
        XCTAssertEqual(deliveries.count, runs, "one delivery per run")
    }

    // MARK: - Helpers

    private func makeSUT(
        producer: [ProducerSpy.Outcome] = [.hold],
        fallback: [ProducerSpy.Outcome] = [.success("fallback")]
    ) -> SUT {
        SUT(producer: ProducerSpy("producer", script: producer), fallback: ProducerSpy("fallback", script: fallback))
    }
}
