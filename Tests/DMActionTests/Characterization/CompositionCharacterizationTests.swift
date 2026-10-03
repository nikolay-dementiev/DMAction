import DMAction
import XCTest

/// Pins what composition does: how often each producer runs, what the consumer receives and
/// which attempt label a success carries: the number of attempts that failed before it in the
/// same run, added to the attempt of the action that was run.
final class CompositionCharacterizationTests: XCTestCase {
    private struct LabelRow {
        /// The call of the primary that succeeds. `nil`: it never succeeds.
        let successOnCall: Int?
        let label: UInt?
        let value: String?

        var position: String { successOnCall.map { "call \($0)" } ?? "no call" }
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
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastLabel, 0, "a first-try success keeps label 0")
    }

    func test_retry_whenEveryAttemptFails_deliversTheErrorOfTheLastAttempt() {
        let errors = (1...4).map { _ in MarkedError() }
        let (producer, consumer) = makeSUT(script: errors.map { .failure($0) })

        producer.action.retry(3).action(consumer.receive)

        XCTAssertEqual(producer.callCount, 4, "the first attempt and three retries")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertTrue(consumer.lastError as? MarkedError === errors[3], "the error of the fourth attempt, not an earlier one")
        XCTAssertNil(consumer.lastLabel, "a failure carries no label")
    }

    func test_retry_whenLaterAttemptSucceeds_stopsAndLabelsTheFailuresBeforeIt() {
        for successOnCall in 2...4 {
            let producer = ProducerSpy.succeeding(onCall: successOnCall)
            let consumer = ConsumerSpy()

            producer.action.retry(3).action(consumer.receive)

            XCTAssertEqual(producer.callCount, successOnCall, "stops at the success on call \(successOnCall)")
            XCTAssertEqual(consumer.count, 1, "one delivery, success on call \(successOnCall)")
            XCTAssertEqual(consumer.lastLabel, UInt(successOnCall - 1), "the failed attempts before call \(successOnCall)")
            XCTAssertEqual(consumer.lastValue, "value", "the payload of call \(successOnCall)")
        }
    }

    func test_retry_whenLaterAttemptSucceeds_deliversThePayloadInOneWrapper() {
        let producer = ProducerSpy.succeeding(onCall: 3)
        let consumer = ConsumerSpy()

        producer.action.retry(3).action(consumer.receive)

        let wrapper = consumer.lastDelivered as? DMActionResultValue
        XCTAssertEqual(wrapper?.value as? String, "value", "one wrapper around the payload, not a wrapper in a wrapper")
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
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastLabel, 0, "label of a first-try success")
    }

    // MARK: - fallbackTo

    func test_fallbackTo_whenPrimarySucceeds_doesNotInvokeFallback() {
        let primary = ProducerSpy(script: [.success("primary")])
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(fallback.callCount, 0, "the fallback does not run after a success")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "primary", "the primary's payload")
        XCTAssertEqual(consumer.lastLabel, 0, "a first-try success keeps label 0")
    }

    func test_fallbackTo_whenPrimaryFails_invokesFallbackOnceWithLabelOne() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(primary.callCount, 1, "the primary runs once")
        XCTAssertEqual(fallback.callCount, 1, "the fallback runs once")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "fallback", "the fallback's payload")
        XCTAssertEqual(consumer.lastLabel, 1, "one failed attempt before the fallback")
    }

    func test_fallbackTo_whenBothFail_deliversTheFallbackError() {
        let fallbackError = MarkedError()
        let primary = ProducerSpy.alwaysFailing(with: MarkedError())
        let fallback = ProducerSpy.alwaysFailing(with: fallbackError)
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertTrue(consumer.lastError as? MarkedError === fallbackError, "the last error wins; the first is dropped")
        XCTAssertNil(consumer.lastLabel, "a failure carries no label")
    }

    // MARK: - Chains

    func test_fallbackTo_afterThreeRetries_labelsEachSuccessByTheFailuresBeforeIt() {
        let rows = [
            LabelRow(successOnCall: 1, label: 0, value: "primary"),
            LabelRow(successOnCall: 2, label: 1, value: "primary"),
            LabelRow(successOnCall: 3, label: 2, value: "primary"),
            LabelRow(successOnCall: 4, label: 3, value: "primary"),
            LabelRow(successOnCall: nil, label: 4, value: "fallback")
        ]
        for row in rows {
            let primary = ProducerSpy.succeeding(onCall: row.successOnCall, with: "primary")
            let fallback = ProducerSpy(script: [.success("fallback")])
            let consumer = ConsumerSpy()

            primary.action.retry(3).fallbackTo(fallback.action).action(consumer.receive)

            XCTAssertEqual(consumer.count, 1, "one delivery, primary succeeds on \(row.position)")
            XCTAssertEqual(consumer.lastLabel, row.label, "label, primary succeeds on \(row.position)")
            XCTAssertEqual(consumer.lastValue, row.value, "payload, primary succeeds on \(row.position)")
            XCTAssertEqual(fallback.callCount, row.successOnCall == nil ? 1 : 0, "fallback calls, \(row.position)")
        }
    }

    func test_fallbackTo_whenTheFallbackIsRetried_countsTheFailuresOfBoth() {
        for successOnCall in 1...3 {
            let primary = ProducerSpy.alwaysFailing()
            let fallback = ProducerSpy.succeeding(onCall: successOnCall, with: "fallback")
            let consumer = ConsumerSpy()

            primary.action.fallbackTo(fallback.action.retry(2)).action(consumer.receive)

            XCTAssertEqual(fallback.callCount, successOnCall, "calls of the retried fallback")
            XCTAssertEqual(consumer.count, 1, "one delivery, fallback succeeds on call \(successOnCall)")
            XCTAssertEqual(
                consumer.lastLabel,
                UInt(successOnCall),
                "the primary's failure and the fallback's failures before its call \(successOnCall)"
            )
        }
    }

    func test_retry_onARetriedAction_repeatsTheInnerRetryAsAUnit() {
        let rows = [
            LabelRow(successOnCall: 1, label: 0, value: "value"),
            LabelRow(successOnCall: 2, label: 1, value: "value"),
            LabelRow(successOnCall: 3, label: 2, value: "value"),
            LabelRow(successOnCall: 4, label: 3, value: "value"),
            LabelRow(successOnCall: nil, label: nil, value: nil)
        ]
        for row in rows {
            let producer = ProducerSpy.succeeding(onCall: row.successOnCall)
            let consumer = ConsumerSpy()

            producer.action.retry(1).retry(1).action(consumer.receive)

            XCTAssertEqual(producer.callCount, row.successOnCall ?? 4, "at most four calls, success on \(row.position)")
            XCTAssertEqual(consumer.count, 1, "one delivery, success on \(row.position)")
            XCTAssertEqual(consumer.lastLabel, row.label, "label, success on \(row.position)")
            XCTAssertEqual(consumer.lastValue, row.value, "payload, success on \(row.position)")
        }
    }

    func test_retry_onAFallbackPair_runsThePairAgain() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy.succeeding(onCall: 2, with: "fallback")
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).retry(1).action(consumer.receive)

        XCTAssertEqual(primary.callCount, 2, "the primary runs again with the pair")
        XCTAssertEqual(fallback.callCount, 2, "the fallback runs again with the pair")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastLabel, 3, "three failed attempts before the fourth call")
    }

    func test_retry_onAFallbackPair_whenThePrimarySucceedsOnTheRerun_labelsItTwo() {
        let primary = ProducerSpy.succeeding(onCall: 2, with: "primary")
        let fallback = ProducerSpy.alwaysFailing()
        let consumer = ConsumerSpy()

        primary.action.fallbackTo(fallback.action).retry(1).action(consumer.receive)

        XCTAssertEqual(fallback.callCount, 1, "the fallback ran once, in the first pair")
        XCTAssertEqual(consumer.lastValue, "primary", "the rerun of the primary delivers")
        XCTAssertEqual(consumer.lastLabel, 2, "the primary and the fallback failed before it")
    }

    func test_fallbackTo_whenNestedRightOrLeft_labelsTheLastActionTheSameEitherWay() {
        let rightNested = ConsumerSpy()
        let leftNested = ConsumerSpy()
        func failing() -> DMButtonAction { ProducerSpy.alwaysFailing().action }
        func succeeding() -> DMButtonAction { ProducerSpy(script: [.success("C")]).action }

        failing().fallbackTo(failing().fallbackTo(succeeding())).action(rightNested.receive)
        failing().fallbackTo(failing()).fallbackTo(succeeding()).action(leftNested.receive)

        XCTAssertEqual(rightNested.count + leftNested.count, 2, "one delivery per run")
        XCTAssertEqual(rightNested.lastLabel, 2, "A.fallbackTo(B.fallbackTo(C))")
        XCTAssertEqual(leftNested.lastLabel, 2, "A.fallbackTo(B).fallbackTo(C)")
    }

    func test_fallbackTo_whenChainedAHundredDeep_runsEveryProducerOnceInOrder() {
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

        let calls = log.events.filter { $0.hasSuffix(" call 1") }
        XCTAssertEqual(spies.map(\.callCount), Array(repeating: 1, count: depth + 1), "every producer runs once")
        XCTAssertEqual(calls, (0...depth).map { "\($0) call 1" }, "in composition order")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "last", "the last fallback delivers")
        XCTAssertEqual(consumer.lastLabel, UInt(depth), "a hundred failed attempts before the last")
    }

    func test_currentAttempt_ofACompositionOrARetry_isTheReceiversAttempt() {
        let receiver = DMActionWithFallback(currentAttempt: 5, { $0(.success("primary")) }, { $0(.success("fallback")) })
        let other = DMButtonAction { $0(.success("other")) }

        XCTAssertEqual(receiver.fallbackTo(other).currentAttempt, 5, "fallbackTo keeps the receiver's attempt")
        XCTAssertEqual(receiver.retry(3).currentAttempt, 5, "retry keeps the receiver's attempt")
        XCTAssertEqual(other.fallbackTo(receiver).currentAttempt, 0, "the attempt of a fallback is not used")
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

    func test_fallbackTo_afterOneRetry_labelsTheFallbackTwo() {
        let primary = ProducerSpy.alwaysFailing()
        let fallback = ProducerSpy(script: [.success("fallback")])
        let consumer = ConsumerSpy()

        primary.action.retry(1).fallbackTo(fallback.action).action(consumer.receive)

        XCTAssertEqual(primary.callCount, 2, "the first attempt and one retry")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastLabel, 2, "two failed attempts before the fallback")
    }

    // MARK: - Entry points

    func test_callSyntax_onBuiltInAction_deliversWhatActionDelivers() {
        let error = MarkedError()
        let succeeded = ConsumerSpy()
        let failed = ConsumerSpy()

        let recovering = ProducerSpy.succeeding(onCall: 2).action.retry(1)
        let failing = ProducerSpy.alwaysFailing(with: error).action

        recovering(completion: succeeded.receive)
        failing(completion: failed.receive)

        XCTAssertEqual(succeeded.count + failed.count, 2, "one delivery per call")
        XCTAssertEqual(succeeded.lastValue, "value", "the payload")
        XCTAssertEqual(succeeded.lastLabel, 1, "the same label as through action")
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
