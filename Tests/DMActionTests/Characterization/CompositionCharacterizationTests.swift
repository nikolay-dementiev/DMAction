import DMAction
import XCTest

/// Pins what composition does today: how often each producer runs, what the consumer
/// receives and which attempt label a success carries. The labels are irregular. They are
/// the released behaviour, so they are pinned as they are.
final class CompositionCharacterizationTests: XCTestCase {
    private struct LabelRow {
        /// The call of the primary that succeeds. 0: it never succeeds.
        let successOnCall: Int
        let label: UInt?
        let value: String?
    }

    // MARK: - A single action

    func test_action_onSuccess_deliversValueWithLabelZero() {
        let (producer, consumer) = makeSUT(script: [.success("value")])

        producer.action.action(consumer.receive)

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "value", "the payload the producer delivered")
        XCTAssertEqual(consumer.lastLabel, 0, "a single action is labelled 0")
    }

    func test_action_onFailure_deliversSameErrorInstanceAndNoLabel() {
        let error = MarkedError()
        let (producer, consumer) = makeSUT(script: [.failure(error)])

        producer.action.action(consumer.receive)

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertTrue(consumer.lastError as? MarkedError === error, "the error instance the producer delivered")
        XCTAssertNil(consumer.lastLabel, "a failure carries no label")
    }

    // MARK: - retry

    func test_retry_whenFirstAttemptSucceeds_invokesProducerOnce() {
        let (producer, consumer) = makeSUT(script: [.success("first")])

        producer.action.retry(3).action(consumer.receive)

        XCTAssertEqual(producer.callCount, 1, "no retry after a success")
        XCTAssertEqual(consumer.lastLabel, 0, "a first-try success keeps label 0")
    }

    func test_retry_whenAlwaysFailing_invokesProducerRetryCountPlusOneTimes() {
        let error = MarkedError()
        let producer = ProducerSpy.alwaysFailing(with: error)
        let consumer = ConsumerSpy()

        producer.action.retry(3).action(consumer.receive)

        XCTAssertEqual(producer.callCount, 4, "the first attempt and three retries")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertTrue(consumer.lastError as? MarkedError === error, "the error of the last attempt")
        XCTAssertNil(consumer.lastLabel, "a failure carries no label")
    }

    func test_retry_whenLaterAttemptSucceeds_stopsAndReportsLegacyLabel() {
        for successOnCall in 2...4 {
            let producer = ProducerSpy.failing(successOnCall - 1, then: "value")
            let consumer = ConsumerSpy()

            producer.action.retry(3).action(consumer.receive)

            XCTAssertEqual(producer.callCount, successOnCall, "stops at the success on call \(successOnCall)")
            XCTAssertEqual(consumer.lastLabel, UInt(successOnCall), "legacy label of call \(successOnCall)")
            XCTAssertEqual(consumer.lastValue, "value", "the payload of call \(successOnCall)")
        }
    }

    func test_retry_withZero_returnsTheReceiver() {
        let (producer, consumer) = makeSUT(script: [.failure(MarkedError())])
        let action = producer.action

        let retried = action.retry(0)
        retried.action(consumer.receive)

        XCTAssertEqual(retried.id, action.id, "retry(0) returns the receiver itself")
        XCTAssertEqual(producer.callCount, 1, "no retry")
    }

    func test_retry_withLargeCountAndImmediateSuccess_invokesProducerOnce() {
        let (producer, consumer) = makeSUT(script: [.success("first")])

        producer.action.retry(200).action(consumer.receive)

        XCTAssertEqual(producer.callCount, 1, "one call")
        XCTAssertEqual(consumer.lastLabel, 0, "label of a first-try success")
    }

    // MARK: - fallbackTo

    func test_fallbackTo_whenPrimarySucceeds_doesNotInvokeFallback() {
        let primary = ProducerSpy(script: [.success("primary")])
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(fallback.callCount, 0, "the fallback does not run after a success")
        XCTAssertEqual(consumer.lastValue, "primary", "the primary's payload")
        XCTAssertEqual(consumer.lastLabel, 0, "a first-try success keeps label 0")
    }

    func test_fallbackTo_whenPrimaryFails_invokesFallbackOnceWithLabelTwo() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(primary.callCount, 1, "the primary runs once")
        XCTAssertEqual(fallback.callCount, 1, "the fallback runs once")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "fallback", "the fallback's payload")
        XCTAssertEqual(consumer.lastLabel, 2, "legacy label of a fallback success")
    }

    func test_fallbackTo_whenBothFail_deliversTheFallbackError() {
        let fallbackError = MarkedError()
        let primary = ProducerSpy.alwaysFailing(with: MarkedError())
        let fallback = ProducerSpy.alwaysFailing(with: fallbackError)
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertTrue(consumer.lastError as? MarkedError === fallbackError, "the last error wins; the first is dropped")
        XCTAssertNil(consumer.lastLabel, "a failure carries no label")
    }

    // MARK: - Chains

    func test_retryThenFallback_reportsLegacyLabels() {
        let rows = [
            LabelRow(successOnCall: 1, label: 0, value: "primary"),
            LabelRow(successOnCall: 2, label: 2, value: "primary"),
            LabelRow(successOnCall: 3, label: 3, value: "primary"),
            LabelRow(successOnCall: 4, label: 4, value: "primary"),
            LabelRow(successOnCall: 0, label: 5, value: "fallback")
        ]
        for row in rows {
            let primary = row.successOnCall == 0
                ? ProducerSpy.alwaysFailing()
                : ProducerSpy.failing(row.successOnCall - 1, then: "primary")
            let fallback = ProducerSpy(script: [.success("fallback")])
            let consumer = ConsumerSpy()

            primary.action.retry(3).fallbackTo(fallback.action).action(consumer.receive)

            XCTAssertEqual(consumer.lastLabel, row.label, "label, primary succeeds on call \(row.successOnCall)")
            XCTAssertEqual(consumer.lastValue, row.value, "payload, primary succeeds on call \(row.successOnCall)")
            XCTAssertEqual(fallback.callCount, row.successOnCall == 0 ? 1 : 0, "fallback calls, row \(row.successOnCall)")
        }
    }

    func test_fallbackToRetriedAction_labelsEverySuccessOfTheFallbackTwo() {
        for failures in 0...2 {
            let primary = ProducerSpy.alwaysFailing()
            let fallback = ProducerSpy.failing(failures, then: "fallback")
            let consumer = ConsumerSpy()

            primary.action.fallbackTo(fallback.action.retry(2)).action(consumer.receive)

            XCTAssertEqual(fallback.callCount, failures + 1, "calls of the retried fallback")
            XCTAssertEqual(consumer.lastLabel, 2, "label when the fallback succeeds on call \(failures + 1)")
        }
    }

    func test_retryOfRetry_keepsTheInnerRetryAsTheUnit() {
        let rows = [
            LabelRow(successOnCall: 1, label: 0, value: "value"),
            LabelRow(successOnCall: 2, label: 2, value: "value"),
            LabelRow(successOnCall: 3, label: 3, value: "value"),
            LabelRow(successOnCall: 4, label: 3, value: "value"),
            LabelRow(successOnCall: 5, label: nil, value: nil)
        ]
        for row in rows {
            let producer = ProducerSpy.failing(row.successOnCall - 1, then: "value")
            let consumer = ConsumerSpy()

            producer.action.retry(1).retry(1).action(consumer.receive)

            XCTAssertEqual(producer.callCount, min(row.successOnCall, 4), "at most four calls, row \(row.successOnCall)")
            XCTAssertEqual(consumer.lastLabel, row.label, "label, success on call \(row.successOnCall)")
            XCTAssertEqual(consumer.lastValue, row.value, "payload, success on call \(row.successOnCall)")
        }
    }

    func test_retryOfFallbackPair_retriesThePair() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy.failing(1, then: "fallback")
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).retry(1).action(consumer.receive)

        XCTAssertEqual(primary.callCount, 2, "the primary runs again with the pair")
        XCTAssertEqual(fallback.callCount, 2, "the fallback runs again with the pair")
        XCTAssertEqual(consumer.lastLabel, 3, "legacy label of the fourth call")
    }

    func test_nestedFallbacks_labelDependsOnTheShape() {
        let rightNested = ConsumerSpy()
        let leftNested = ConsumerSpy()
        func failing() -> DMButtonAction { ProducerSpy.alwaysFailing().action }
        func succeeding() -> DMButtonAction { ProducerSpy(script: [.success("C")]).action }

        failing().fallbackTo(failing().fallbackTo(succeeding())).action(rightNested.receive)
        failing().fallbackTo(failing()).fallbackTo(succeeding()).action(leftNested.receive)

        XCTAssertEqual(rightNested.lastLabel, 2, "A.fallbackTo(B.fallbackTo(C))")
        XCTAssertEqual(leftNested.lastLabel, 3, "A.fallbackTo(B).fallbackTo(C)")
    }

    func test_deepFallbackChains_runEveryProducerOnceInOrder() {
        let depth = 100
        let log = EventLog()
        let spies = (0...depth).map { index in
            index == depth
                ? ProducerSpy("\(index)", log: log, script: [.success("last")])
                : ProducerSpy.alwaysFailing(name: "\(index)", log: log)
        }
        var leftNested: any DMAction = spies[0].action
        for spy in spies.dropFirst() {
            leftNested = leftNested.fallbackTo(spy.action)
        }
        let consumer = ConsumerSpy()

        leftNested.action(consumer.receive)

        XCTAssertEqual(spies.map(\.callCount), Array(repeating: 1, count: depth + 1), "every producer runs once")
        XCTAssertEqual(log.events.prefix(3), ["0 call 1", "1 call 1", "2 call 1"], "in composition order")
        XCTAssertEqual(consumer.lastValue, "last", "the last fallback delivers")
        XCTAssertEqual(consumer.lastLabel, UInt(depth) + 1, "legacy label of a left-nested chain")
    }

    // MARK: - Running

    func test_composition_alone_invokesNothing() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy(script: [.success("fallback")])

        _ = primary.action.retry(2).fallbackTo(fallback.action)

        XCTAssertEqual(primary.callCount + fallback.callCount, 0, "composing runs no producer")
    }

    func test_composedAction_runTwice_repeatsEveryAttempt() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()
        let action = primary.action.retry(1).fallbackTo(fallback.action)

        action.action(consumer.receive)
        action.action(consumer.receive)

        XCTAssertEqual(primary.callCount, 4, "two attempts per run")
        XCTAssertEqual(fallback.callCount, 2, "one fallback per run")
        XCTAssertEqual(consumer.count, 2, "one delivery per run")
    }

    func test_retryOnceThenFallback_labelsTheFallbackThree() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()

        primary.action.retry(1).fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(primary.callCount, 2, "the first attempt and one retry")
        XCTAssertEqual(consumer.lastLabel, 3, "legacy label of the fallback after two attempts")
    }

    // MARK: - Entry points

    func test_callSyntax_onBuiltInAction_deliversWhatActionDelivers() {
        let error = MarkedError()
        let succeeded = ConsumerSpy()
        let failed = ConsumerSpy()

        let recovering = ProducerSpy.failing(1, then: "value").action.retry(1)
        let failing = ProducerSpy.alwaysFailing(with: error).action

        recovering(completion: succeeded.receive)
        failing(completion: failed.receive)

        XCTAssertEqual(succeeded.lastValue, "value", "the payload")
        XCTAssertEqual(succeeded.lastLabel, 2, "the same legacy label as through action")
        XCTAssertTrue(failed.lastError as? MarkedError === error, "a failure keeps its error instance")
    }

    func test_simpleAction_onBuiltInAction_runsTheChainAndDropsTheResult() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy.alwaysFailing()

        primary.action.retry(1).fallbackTo(fallback.action).simpleAction()

        XCTAssertEqual(primary.callCount, 2, "the primary and its retry ran")
        XCTAssertEqual(fallback.callCount, 1, "the fallback ran; its failure went nowhere")
    }

    // MARK: - Helpers

    private func makeSUT(script: [ProducerSpy.Outcome]) -> (producer: ProducerSpy, consumer: ConsumerSpy) {
        (ProducerSpy(script: script), ConsumerSpy())
    }
}
