import DMAction
import XCTest

/// Pins what the public fallback initializer, custom conformers and the value types do today.
final class ConformerCharacterizationTests: XCTestCase {
    /// A conformer with computed requirements that counts how often they are read, and in
    /// which order.
    private final class CountingAction: DMAction {
        private(set) var actionReads = 0
        private(set) var attemptReads = 0
        private(set) var reads: [String] = []
        let id = UUID()
        private let work: ActionType

        init(_ work: @escaping ActionType) {
            self.work = work
        }

        var currentAttempt: UInt {
            attemptReads += 1
            reads.append("currentAttempt")
            return 0
        }

        var action: ActionType {
            actionReads += 1
            reads.append("action")
            return work
        }
    }

    /// A conformer that supplies its own `simpleAction`.
    private struct SilentAction: DMAction {
        let currentAttempt: UInt = 0
        let id = UUID()
        let action: ActionType
        let simpleAction: () -> Void
    }

    /// A conformer that starts counting from the attempt it is given.
    private struct ActionAtAttempt: DMAction {
        let currentAttempt: UInt
        let id = UUID()
        let action: ActionType
    }

    /// A value that reports a label through the protocol, not through the library's wrapper.
    private struct LabelledValue: DMActionResultValueProtocol {
        var attemptCount: UInt? { 9 }
    }

    private let succeed: DMButtonAction.ActionType = { $0(.success("primary")) }
    private let fail: DMButtonAction.ActionType = { $0(.failure(MarkedError())) }
    private let succeedAsFallback: DMButtonAction.ActionType = { $0(.success("fallback")) }
    private let succeedWithOwnLabel: DMButtonAction.ActionType = {
        $0(.success(DMActionResultValue(value: "labelled", attemptCount: 9)))
    }

    // MARK: - The public fallback initializer

    func test_publicInit_withRawClosures_labelsThePrimaryWithItsAttemptAndTheFallbackWithTheNext() {
        let primaryRun = ConsumerSpy()
        let fallbackRun = ConsumerSpy()

        DMActionWithFallback(currentAttempt: 5, succeed, succeedAsFallback).action(primaryRun.receive)
        DMActionWithFallback(currentAttempt: 5, fail, succeedAsFallback).action(fallbackRun.receive)

        XCTAssertEqual(primaryRun.lastLabel, 5, "a primary success without a label takes the given attempt")
        XCTAssertEqual(fallbackRun.lastLabel, 6, "a fallback success takes the next one")
        XCTAssertEqual(fallbackRun.lastValue, "fallback", "the fallback's payload")
    }

    func test_publicInit_whenAProducerSuppliesALabel_overwritesItInBothPositions() {
        let primaryRun = ConsumerSpy()
        let fallbackRun = ConsumerSpy()

        DMActionWithFallback(currentAttempt: 5, succeedWithOwnLabel, succeedAsFallback).action(primaryRun.receive)
        DMActionWithFallback(currentAttempt: 5, fail, succeedWithOwnLabel).action(fallbackRun.receive)

        XCTAssertEqual(primaryRun.lastLabel, 5, "a label the primary supplied is overwritten with the given attempt")
        XCTAssertEqual(fallbackRun.lastLabel, 6, "a label on a fallback success is overwritten")
        XCTAssertEqual(fallbackRun.lastValue, "labelled", "the payload is unwrapped from the supplied wrapper")
    }

    /// A composed action handed to the initializer as a closure is one attempt of the outer run:
    /// the failures inside it are not counted. The same chain built with `fallbackTo` is counted.
    func test_publicInit_withAComposedActionAsAClosure_countsItAsOneAttempt() {
        let primaryRun = ConsumerSpy()
        let fallbackRun = ConsumerSpy()
        let chainRun = ConsumerSpy()
        let fallback = ProducerSpy(script: [.success("fallback")]).action

        let recovering = ProducerSpy.succeeding(onCall: 2, with: "primary").action.retry(1)
        DMActionWithFallback(currentAttempt: 0, recovering.action, fallback.action).action(primaryRun.receive)
        let failing = ProducerSpy.alwaysFailing().action.retry(1)
        DMActionWithFallback(currentAttempt: 0, failing.action, fallback.action).action(fallbackRun.receive)
        let recoveringInAChain = ProducerSpy.succeeding(onCall: 2, with: "primary").action.retry(1)
        recoveringInAChain.fallbackTo(fallback).action(chainRun.receive)

        XCTAssertEqual(primaryRun.lastLabel, 0, "the retry inside the closure is not counted")
        XCTAssertEqual(fallbackRun.lastLabel, 1, "the failed closure counts as one attempt")
        XCTAssertEqual(chainRun.lastLabel, 1, "built with fallbackTo, the failed first call is counted")
    }

    func test_publicInit_whenUsedAsAReceiver_keepsItsLabelsAndLabelsTheAddedFallbackAfterThem() {
        let afterPrimary = ConsumerSpy()
        let afterFallback = ConsumerSpy()
        let afterBoth = ConsumerSpy()
        let last = DMButtonAction(succeedAsFallback)

        DMActionWithFallback(currentAttempt: 5, succeed, succeedAsFallback).fallbackTo(last).action(afterPrimary.receive)
        DMActionWithFallback(currentAttempt: 5, fail, succeedAsFallback).fallbackTo(last).action(afterFallback.receive)
        DMActionWithFallback(currentAttempt: 5, fail, fail).fallbackTo(last).action(afterBoth.receive)

        XCTAssertEqual(afterPrimary.lastLabel, 5, "the primary keeps the given attempt")
        XCTAssertEqual(afterFallback.lastLabel, 6, "its own fallback keeps the next one")
        XCTAssertEqual(afterBoth.lastLabel, 7, "the added fallback takes the one after that")
    }

    func test_publicInit_whenUsedAsAFallback_labelsItsSuccessesByTheFailuresBeforeThem() {
        let primaryRun = ConsumerSpy()
        let fallbackRun = ConsumerSpy()
        let failing = DMButtonAction(fail)

        failing.fallbackTo(DMActionWithFallback(currentAttempt: 5, succeed, succeedAsFallback)).action(primaryRun.receive)
        failing.fallbackTo(DMActionWithFallback(currentAttempt: 5, fail, succeedAsFallback)).action(fallbackRun.receive)

        XCTAssertEqual(primaryRun.lastLabel, 1, "the given attempt is not used: one failure before it")
        XCTAssertEqual(fallbackRun.lastLabel, 2, "two failures before its fallback")
    }

    // MARK: - Custom conformers: when their properties are read

    func test_fallbackTo_onCustomConformers_readsTheirPropertiesOnceAtComposition() {
        let receiver = makeSUT()
        let fallback = makeSUT()

        _ = receiver.fallbackTo(fallback)

        XCTAssertEqual(receiver.attemptReads, 1, "the receiver's attempt")
        XCTAssertEqual(receiver.actionReads, 1, "the receiver's action")
        XCTAssertEqual(fallback.actionReads, 1, "the fallback's action")
        XCTAssertEqual(fallback.attemptReads, 0, "the fallback's attempt is not used")
    }

    func test_retry_onCustomConformer_readsItsActionOnceAtComposition() {
        let retried = makeSUT()
        let untouched = makeSUT()

        _ = retried.retry(3)
        _ = untouched.retry(0)

        XCTAssertEqual(retried.actionReads, 1, "the action is read once, whatever the count")
        XCTAssertEqual(retried.attemptReads, 1, "the attempt is read once")
        XCTAssertEqual(untouched.actionReads + untouched.attemptReads, 0, "retry(0) reads nothing")
    }

    /// The producer never completes, so a read that waited for a result would not happen.
    func test_callSyntax_onCustomConformer_readsItsActionThenItsAttemptAtTheCall() {
        let receiver = makeSUT { _ in }
        let readsBeforeTheCall = receiver.reads

        receiver { _ in }

        XCTAssertEqual(readsBeforeTheCall, [], "nothing is read before the call")
        XCTAssertEqual(receiver.reads, ["action", "currentAttempt"], "the action, then the attempt, both at the call")
    }

    func test_callSyntax_onCustomConformer_whenTheResultArrives_readsNothingMore() {
        let consumer = ConsumerSpy()
        let receiver = makeSUT()

        receiver(completion: consumer.receive)

        XCTAssertEqual(consumer.count, 1, "the result arrived")
        XCTAssertEqual(receiver.reads, ["action", "currentAttempt"], "each read once, at the call, none at the delivery")
    }

    func test_retry_onCustomConformer_whenRun_readsItsActionOnceForAllAttempts() {
        let producer = ProducerSpy.succeeding(onCall: 4)
        let receiver = makeSUT(producer.produce)
        let consumer = ConsumerSpy()

        receiver.retry(5).action(consumer.receive)

        XCTAssertEqual(producer.callCount, 4, "four attempts ran")
        XCTAssertEqual(consumer.lastLabel, 3, "three failed before the success")
        XCTAssertEqual(receiver.reads, ["currentAttempt", "action"], "each read once, at composition, not per attempt")
    }

    /// The default `simpleAction` calls the conformer's own `action`: it is not a guarded run.
    func test_simpleAction_onCustomConformer_readsItsActionOnceAndNotItsAttempt() {
        let receiver = makeSUT()
        let readsBeforeTheCall = receiver.reads

        receiver.simpleAction()

        XCTAssertEqual(readsBeforeTheCall, [], "nothing is read before the call")
        XCTAssertEqual(receiver.reads, ["action"], "the action, once, and not the attempt")
    }

    // MARK: - Custom conformers: what they deliver

    func test_fallbackTo_onCustomConformer_labelsAFirstTrySuccessZero() {
        let consumer = ConsumerSpy()

        makeSUT().fallbackTo(DMButtonAction(succeedAsFallback)).action(consumer.receive)

        XCTAssertEqual(consumer.lastLabel, 0)
    }

    func test_callSyntax_onCustomConformer_wrapsTheResultWithItsAttempt() {
        let consumer = ConsumerSpy()
        let receiver = makeSUT()

        receiver(completion: consumer.receive)

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastLabel, 0, "call syntax wraps the result with the conformer's attempt")
        XCTAssertEqual(consumer.lastValue, "primary", "and keeps the payload")
    }

    func test_callSyntax_withANonZeroAttempt_labelsFromThatAttempt() {
        let customRun = ConsumerSpy()
        let builtInRun = ConsumerSpy()
        let custom = ActionAtAttempt(currentAttempt: 7, action: succeed)
        let builtIn = DMActionWithFallback(currentAttempt: 5, fail, succeedAsFallback)

        custom(completion: customRun.receive)
        builtIn(completion: builtInRun.receive)

        XCTAssertEqual(customRun.lastLabel, 7, "a third-party action's own attempt")
        XCTAssertEqual(builtInRun.lastLabel, 6, "the given attempt plus the failed primary")
    }

    func test_customConformer_whenItsProducerSuppliesALabel_overwritesItThroughCallSyntaxAndComposition() {
        let called = ConsumerSpy()
        let composed = ConsumerSpy()
        let receiver = makeSUT(succeedWithOwnLabel)

        receiver(completion: called.receive)
        receiver.fallbackTo(DMButtonAction(succeedAsFallback)).action(composed.receive)

        XCTAssertEqual(called.lastLabel, 0, "through call syntax: the conformer's attempt")
        XCTAssertEqual(composed.lastLabel, 0, "through a fallback composition: no failure before it")
    }

    func test_simpleAction_whenAConformerSuppliesItsOwn_runsThatOne() {
        var ownCalls = 0
        let producer = ProducerSpy(script: [.success("value")])
        let action: any DMAction = SilentAction(action: producer.produce, simpleAction: { ownCalls += 1 })

        action.simpleAction()

        XCTAssertEqual(ownCalls, 1, "the conformer's own simpleAction ran")
        XCTAssertEqual(producer.callCount, 0, "the default, which runs the action, did not")
    }

    // MARK: - Values

    func test_unwrapValue_withNestedWrappers_returnsTheInnermostValue() {
        let inner = DMActionResultValue(value: "deep", attemptCount: 1)
        let result: DMButtonAction.ResultType = .success(DMActionResultValue(value: inner, attemptCount: 2))

        guard case .success(let value) = result.unwrapValue() else {
            return XCTFail("a success stays a success")
        }
        XCTAssertEqual(value as? String, "deep")
    }

    func test_attemptCount_afterUnwrapValue_isGone() {
        let result: DMButtonAction.ResultType = .success(DMActionResultValue(value: "value", attemptCount: 3))

        XCTAssertEqual(result.attemptCount, 3, "the wrapped result carries the label")
        XCTAssertNil(result.unwrapValue().attemptCount, "the unwrapped result does not")
    }

    func test_unwrapValue_onAFailure_keepsTheErrorInstance() {
        let error = MarkedError()
        let result: DMButtonAction.ResultType = .failure(error)

        guard case .failure(let unwrapped) = result.unwrapValue() else {
            return XCTFail("a failure stays a failure")
        }
        XCTAssertTrue(unwrapped as? MarkedError === error)
    }

    func test_resultValue_createdWithoutACount_hasNone() {
        XCTAssertNil(DMActionResultValue(value: "value").attemptCount)
    }

    func test_valueProtocol_withoutACountOfItsOwn_reportsNone() {
        struct PlainValue: DMActionResultValueProtocol {}

        XCTAssertNil(PlainValue().attemptCount)
    }

    func test_buttonAction_whenItsProducerSuppliesALabel_overwritesIt() {
        let consumer = ConsumerSpy()

        DMButtonAction(succeedWithOwnLabel).action(consumer.receive)

        XCTAssertEqual(consumer.lastLabel, 0, "the action stamps its own attempt over the supplied 9")
        XCTAssertEqual(consumer.lastValue, "labelled", "and keeps the payload")
    }

    func test_run_whenAProducerDeliversNestedWrappers_deliversOneWrapperAroundTheInnermostValue() {
        let consumer = ConsumerSpy()
        let nested = DMActionResultValue(value: DMActionResultValue(value: "deep", attemptCount: 1), attemptCount: 2)

        DMButtonAction(fail).fallbackTo(DMButtonAction { $0(.success(nested)) }).action(consumer.receive)

        let delivered = consumer.lastDelivered as? DMActionResultValue
        XCTAssertEqual(delivered?.value as? String, "deep", "one wrapper, around the innermost value")
        XCTAssertEqual(delivered?.attemptCount, 1, "the run's label: one failed attempt before it")
    }

    func test_run_whenNestedWrappersArriveFromAnotherThread_deliversOneWrapperAroundTheInnermostValue() {
        let primary = ProducerSpy.alwaysFailing()
        let fallbackCalls = LockedCounter()
        let completers = DispatchGroup()
        let consumer = ConsumerSpy()
        let nested = DMActionResultValue(value: DMActionResultValue(value: "deep", attemptCount: 1), attemptCount: 2)
        let fromAnotherThread = DMButtonAction { completion in
            fallbackCalls.increment()
            completers.enter()
            BackgroundCaller {
                completion(.success(nested))
                completers.leave()
            }
            .start()
        }

        primary.action.fallbackTo(fromAnotherThread).action(consumer.receive)
        let completersReturned = completers.wait(timeout: .now() + 5)

        let delivered = consumer.lastDelivered as? DMActionResultValue
        XCTAssertEqual(completersReturned, .success, "the completing thread returned from the completion")
        XCTAssertEqual(primary.callCount, 1, "the primary ran once")
        XCTAssertEqual(fallbackCalls.count, 1, "the fallback ran once")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(delivered?.value as? String, "deep", "one wrapper, around the innermost value")
        XCTAssertEqual(delivered?.attemptCount, 1, "the run's label: one failed attempt before it")
    }

    func test_attemptCount_onAnotherConformerOfTheValueProtocol_isNil() {
        let result: DMButtonAction.ResultType = .success(LabelledValue())

        XCTAssertNil(result.attemptCount)
    }

    func test_simpleClosureInit_whenRetried_runsOnceAndDeliversThePlaceholder() {
        var calls = 0
        let consumer = ConsumerSpy()

        DMButtonAction { calls += 1 }.retry(3).action(consumer.receive)

        guard case .success(let value)? = consumer.deliveries.last?.unwrapValue() else {
            return XCTFail("a simple closure always succeeds")
        }
        XCTAssertEqual(calls, 1, "a success is never retried")
        XCTAssertTrue(value is PlaceholderCopyable, "the payload is the placeholder")
        XCTAssertEqual(consumer.lastLabel, 0, "labelled as a first attempt")
    }

    func test_id_whenCopiedOrComposed_isSharedByCopiesAndNewForCompositions() {
        let action = ProducerSpy(script: [.success("value")]).action
        let other = ProducerSpy(script: [.success("value")]).action
        let copy = action

        XCTAssertEqual(copy.id, action.id, "a copy shares the id")
        XCTAssertNotEqual(other.id, action.id, "two actions created separately differ")
        XCTAssertNotEqual(action.fallbackTo(copy).id, action.fallbackTo(copy).id, "two compositions differ")
        XCTAssertNotEqual(action.fallbackTo(copy).id, action.id, "fallbackTo mints a new id")
        XCTAssertNotEqual(action.retry(1).id, action.id, "retry mints a new id")
    }

    // MARK: - Helpers

    private func makeSUT(_ work: DMButtonAction.ActionType? = nil) -> CountingAction {
        CountingAction(work ?? succeed)
    }
}
