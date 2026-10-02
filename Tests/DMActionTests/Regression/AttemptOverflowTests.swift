import DMAction
import XCTest

/// The attempt number used to trap when it went past `UInt.max`, in two places: when
/// `fallbackTo` composes an action whose attempt is `UInt.max`, and when the primary of such
/// an action fails at run time. It now stops at `UInt.max`.
final class AttemptOverflowTests: XCTestCase {
    /// A third-party action that starts counting from the attempt it is given.
    private struct ActionAtAttempt: DMAction {
        let currentAttempt: UInt
        let id = UUID()
        let action: ActionType
    }

    private struct SUT {
        let primary: ProducerSpy
        let fallback: ProducerSpy
        let consumer = ConsumerSpy()
    }

    // MARK: - A failing primary, at run time

    func test_run_whenThePrimaryFailsAtTheMaximumAttempt_labelsTheFallbackMaximum() {
        let sut = makeSUT(primary: [.failure(MarkedError())])

        DMActionWithFallback(currentAttempt: .max, sut.primary.produce, sut.fallback.produce).action(sut.consumer.receive)

        XCTAssertEqual(sut.primary.callCount, 1, "the primary runs once")
        XCTAssertEqual(sut.fallback.callCount, 1, "the fallback runs once")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the fallback's payload")
        XCTAssertEqual(sut.consumer.lastLabel, .max, "the label stops at the maximum")
    }

    func test_run_whenThePrimaryFailsOneBelowTheMaximum_labelsTheFallbackMaximum() {
        let sut = makeSUT(primary: [.failure(MarkedError())])

        DMActionWithFallback(currentAttempt: .max - 1, sut.primary.produce, sut.fallback.produce)
            .action(sut.consumer.receive)

        XCTAssertEqual(sut.fallback.callCount, 1, "the fallback runs once")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastLabel, .max, "one below the maximum, plus one")
    }

    func test_run_whenThePrimarySucceedsNearTheMaximum_keepsItsAttemptAndSkipsTheFallback() {
        for attempt in [UInt.max - 1, .max] {
            let sut = makeSUT(primary: [.success("primary")])

            DMActionWithFallback(currentAttempt: attempt, sut.primary.produce, sut.fallback.produce)
                .action(sut.consumer.receive)

            XCTAssertEqual(sut.fallback.callCount, 0, "no fallback after a success, attempt \(attempt)")
            XCTAssertEqual(sut.consumer.count, 1, "one delivery, attempt \(attempt)")
            XCTAssertEqual(sut.consumer.lastLabel, attempt, "a primary success is not incremented, attempt \(attempt)")
        }
    }

    // MARK: - fallbackTo, at composition

    func test_fallbackTo_onAnActionAtTheMaximumAttempt_composesAndLabelsTheAddedFallbackMaximum() {
        let sut = makeSUT(primary: [.failure(MarkedError())], fallback: [.failure(MarkedError())])
        let last = ProducerSpy("last", script: [.success("last")])
        let receiver = DMActionWithFallback(currentAttempt: .max, sut.primary.produce, sut.fallback.produce)

        let composed = receiver.fallbackTo(last.action)
        composed.action(sut.consumer.receive)

        XCTAssertEqual(composed.currentAttempt, .max, "the composed attempt stops at the maximum")
        XCTAssertEqual(last.callCount, 1, "the added fallback runs once")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "last", "the added fallback's payload")
        XCTAssertEqual(sut.consumer.lastLabel, .max, "labelled at the maximum")
    }

    func test_fallbackTo_oneBelowTheMaximum_whenEveryActionButTheLastFails_labelsTheLastMaximum() {
        let sut = makeSUT(primary: [.failure(MarkedError())], fallback: [.failure(MarkedError())])
        let last = ProducerSpy("last", script: [.success("last")])
        let receiver = DMActionWithFallback(currentAttempt: .max - 1, sut.primary.produce, sut.fallback.produce)

        let composed = receiver.fallbackTo(last.action)
        composed.action(sut.consumer.receive)

        XCTAssertEqual(composed.currentAttempt, .max, "one below the maximum, plus one")
        XCTAssertEqual([sut.primary, sut.fallback, last].map(\.callCount), [1, 1, 1], "each action runs once")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastLabel, .max, "the last fallback stops at the maximum")
    }

    // MARK: - retry

    func test_retry_onACustomActionAtTheMaximumAttempt_runsEveryAttemptAndLabelsTheMaximum() {
        let producer = ProducerSpy.succeeding(onCall: 3)
        let consumer = ConsumerSpy()
        let action = ActionAtAttempt(currentAttempt: .max, action: producer.produce)

        action.retry(2).action(consumer.receive)

        XCTAssertEqual(producer.callCount, 3, "the first attempt and two retries")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "value", "the payload of the third call")
        XCTAssertEqual(consumer.lastLabel, .max, "labelled at the maximum")
    }

    // MARK: - Helpers

    private func makeSUT(
        primary: [ProducerSpy.Outcome],
        fallback: [ProducerSpy.Outcome] = [.success("fallback")]
    ) -> SUT {
        SUT(primary: ProducerSpy("primary", script: primary), fallback: ProducerSpy("fallback", script: fallback))
    }
}
