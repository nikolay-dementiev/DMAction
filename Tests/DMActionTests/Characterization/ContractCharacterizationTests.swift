import DMAction
import XCTest

/// Pins the execution contract as released: ordering, re-entrancy, threads, duplicate and
/// missing completions, cancellation and lifetime.
final class ContractCharacterizationTests: XCTestCase {

    // MARK: - Ordering

    func test_run_withSynchronousProducers_startsTheFallbackAfterThePrimaryReturns() {
        let log = EventLog()
        let primary = ProducerSpy.alwaysFailing(name: "primary", log: log)
        let fallback = ProducerSpy("fallback", log: log, script: [.success("value")])
        let consumer = ConsumerSpy(log: log)

        primary.action.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(
            log.events,
            ["primary call 1", "primary return 1", "fallback call 1", "fallback return 1", "consumer"]
        )
    }

    func test_run_withSynchronousProducers_finishesBeforeTheStartingCallReturns() {
        let (producer, consumer) = makeSUT(script: [.failure(MarkedError()), .failure(MarkedError()), .success("value")])

        producer.action.retry(2).action(consumer.receive)

        XCTAssertEqual(consumer.lastValue, "value")
    }

    func test_completion_thatRunsTheSameActionAgain_startsAnIndependentRun() {
        let producer = ProducerSpy(script: [.failure(MarkedError()), .success("first"), .success("second")])
        let action = producer.action.retry(1)
        var values: [String] = []

        action.action { first in
            values.append(ConsumerSpy.text(of: first) ?? "no text")
            action.action { second in
                values.append(ConsumerSpy.text(of: second) ?? "no text")
            }
        }

        XCTAssertEqual(producer.callCount, 3, "two calls in the first run, one in the second")
        XCTAssertEqual(values, ["first", "second"], "each run delivers its own result")
    }

    // MARK: - Threads

    func test_action_completedOnAnotherThread_deliversOnThatThread() {
        let delivered = expectation(description: "the consumer completion ran")
        var deliveryThread: Thread?
        var value: String?
        var caller: BackgroundCaller?
        let action = DMButtonAction { completion in
            let background = BackgroundCaller {
                completion(.success("background"))
            }
            caller = background
            background.start()
        }

        action.action { result in
            deliveryThread = Thread.current
            value = ConsumerSpy.text(of: result)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)

        XCTAssertNotNil(deliveryThread, "the consumer completion ran")
        XCTAssertTrue(deliveryThread === caller?.thread, "delivered on the thread the producer completed on")
        XCTAssertFalse(deliveryThread === Thread.current, "which is not the thread that started the run")
        XCTAssertEqual(value, "background", "the payload the producer delivered")
    }

    // MARK: - Missing, duplicate and cancelled completions

    func test_producer_thatHoldsItsCompletions_suspendsTheRunUntilEachIsCompletedByHand() throws {
        let (producer, consumer) = makeSUT(script: [.hold])

        producer.action.retry(1).action(consumer.receive)
        let callsWhileHeld = producer.callCount
        let deliveriesWhileHeld = consumer.count
        let firstAttempt = try XCTUnwrap(producer.heldCompletions.first, "the producer kept its completion")
        firstAttempt(.failure(MarkedError()))
        let callsAfterLateFailure = producer.callCount
        let secondAttempt = try XCTUnwrap(producer.heldCompletions.last, "the retry's completion is held too")
        secondAttempt(.success("late"))

        XCTAssertEqual(callsWhileHeld, 1, "nothing retries while the completion is held")
        XCTAssertEqual(deliveriesWhileHeld, 0, "nothing is delivered while the completion is held")
        XCTAssertEqual(callsAfterLateFailure, 2, "a late failure starts the retry")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "late", "the run continues from the late completion")
    }

    func test_retry_onCancellationError_retriesLikeAnyOtherFailure() {
        let (producer, consumer) = makeSUT(script: [.failure(CancellationError()), .success("value")])

        producer.action.retry(1).action(consumer.receive)

        XCTAssertEqual(producer.callCount, 2, "a cancellation error is retried")
        XCTAssertEqual(consumer.lastValue, "value", "the payload of the retry")
    }

    func test_fallbackTo_whenThePrimaryFailsTwice_runsTheFallbackOnce() {
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
            completion(.failure(MarkedError()))
        }

        primary.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(fallback.callCount, 1, "the first completion of the primary starts the fallback, the second is ignored")
        XCTAssertEqual(consumer.count, 1, "one delivery")
    }

    // MARK: - Lifetime

    func test_run_afterCompletion_releasesWhatItsClosuresCaptured() {
        final class Token {}
        weak var weakToken: Token?
        do {
            let token = Token()
            weakToken = token
            let primary = DMButtonAction { completion in
                _ = token
                completion(.failure(MarkedError()))
            }
            let fallback = DMButtonAction { completion in
                completion(.success("value"))
            }
            primary.retry(2).fallbackTo(fallback).action { _ in
                _ = token
            }
        }

        XCTAssertNil(weakToken)
    }

    // MARK: - Helpers

    private func makeSUT(script: [ProducerSpy.Outcome]) -> (producer: ProducerSpy, consumer: ConsumerSpy) {
        (ProducerSpy(script: script), ConsumerSpy())
    }
}
