import DMAction
import XCTest

/// Pins what the public fallback initializer, custom conformers and the value types do today.
final class ConformerCharacterizationTests: XCTestCase {
    /// A conformer with computed requirements that counts how often they are read.
    private final class CountingAction: DMAction {
        private(set) var actionReads = 0
        private(set) var attemptReads = 0
        let id = UUID()
        private let work: ActionType

        init(_ work: @escaping ActionType) {
            self.work = work
        }

        var currentAttempt: UInt {
            attemptReads += 1
            return 0
        }

        var action: ActionType {
            actionReads += 1
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

    func test_publicInit_whenAProducerSuppliesALabel_keepsThePrimarysAndOverwritesTheFallbacks() {
        let primaryRun = ConsumerSpy()
        let fallbackRun = ConsumerSpy()

        DMActionWithFallback(currentAttempt: 5, succeedWithOwnLabel, succeedAsFallback).action(primaryRun.receive)
        DMActionWithFallback(currentAttempt: 5, fail, succeedWithOwnLabel).action(fallbackRun.receive)

        XCTAssertEqual(primaryRun.lastLabel, 9, "a label on a primary success is kept")
        XCTAssertEqual(fallbackRun.lastLabel, 6, "a label on a fallback success is overwritten")
        XCTAssertEqual(fallbackRun.lastValue, "labelled", "the payload is unwrapped from the supplied wrapper")
    }

    func test_publicInit_withComposedActions_keepsThePrimarysLabelAndStampsTheFallback() {
        let primaryRun = ConsumerSpy()
        let fallbackRun = ConsumerSpy()
        let fallback = ProducerSpy(script: [.success("fallback")]).action

        let recovering = ProducerSpy.failing(1, then: "primary").action.retry(1)
        DMActionWithFallback(currentAttempt: 0, recovering.action, fallback.action).action(primaryRun.receive)
        let failing = ProducerSpy.alwaysFailing().action.retry(1)
        DMActionWithFallback(currentAttempt: 0, failing.action, fallback.action).action(fallbackRun.receive)

        XCTAssertEqual(primaryRun.lastLabel, 2, "the label of the composed primary's second call")
        XCTAssertEqual(fallbackRun.lastLabel, 1, "the fallback takes the given attempt plus one")
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

    func test_retry_onCustomConformer_readsItsActionOncePerAttemptAtComposition() {
        let retried = makeSUT()
        let untouched = makeSUT()

        _ = retried.retry(3)
        _ = untouched.retry(0)

        XCTAssertEqual(retried.actionReads, 4, "one read per attempt")
        XCTAssertEqual(retried.attemptReads, 1, "the attempt is read once")
        XCTAssertEqual(untouched.actionReads + untouched.attemptReads, 0, "retry(0) reads nothing")
    }

    func test_callSyntax_onCustomConformer_readsItsActionAtTheCall() {
        let receiver = makeSUT()
        let readsBeforeTheCall = receiver.actionReads

        receiver { _ in }

        XCTAssertEqual(readsBeforeTheCall, 0, "nothing is read before the call")
        XCTAssertEqual(receiver.actionReads, 1, "the action is read when the call is made")
        XCTAssertEqual(receiver.attemptReads, 1, "the attempt is read when a success arrives without a label")
    }

    // MARK: - Custom conformers: what they deliver

    func test_fallbackTo_onCustomConformer_labelsAFirstTrySuccessOne() {
        let consumer = ConsumerSpy()

        makeSUT().fallbackTo(DMButtonAction(succeedAsFallback)).action(consumer.receive)

        XCTAssertEqual(consumer.lastLabel, 1)
    }

    func test_customConformer_deliversItsRawResultThroughActionAndAWrappedOneThroughCallSyntax() {
        let raw = ConsumerSpy()
        let wrapped = ConsumerSpy()
        let receiver = makeSUT()

        receiver.action(raw.receive)
        receiver(completion: wrapped.receive)

        XCTAssertNil(raw.lastLabel, "the raw action delivers what the conformer produced")
        XCTAssertEqual(wrapped.lastLabel, 0, "call syntax wraps it with the conformer's attempt")
        XCTAssertEqual(wrapped.lastValue, "primary", "and keeps the payload")
    }

    func test_customConformer_withItsOwnLabel_keepsItOnEveryPath() {
        let raw = ConsumerSpy()
        let called = ConsumerSpy()
        let composed = ConsumerSpy()
        let receiver = makeSUT(succeedWithOwnLabel)

        receiver.action(raw.receive)
        receiver(completion: called.receive)
        receiver.fallbackTo(DMButtonAction(succeedAsFallback)).action(composed.receive)

        XCTAssertEqual(raw.lastLabel, 9, "through the raw action")
        XCTAssertEqual(called.lastLabel, 9, "through call syntax")
        XCTAssertEqual(composed.lastLabel, 9, "through a fallback composition")
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

    func test_attemptCount_onAnotherConformerOfTheValueProtocol_isNil() {
        let result: DMButtonAction.ResultType = .success(LabelledValue())

        XCTAssertNil(result.attemptCount)
    }

    func test_simpleClosureInit_deliversThePlaceholderAndIsNeverRetried() {
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

    func test_identity_copySharesTheIdAndCompositionMintsANewOne() {
        let action = ProducerSpy(script: [.success("value")]).action
        let copy = action

        XCTAssertEqual(copy.id, action.id, "a copy shares the id")
        XCTAssertNotEqual(action.fallbackTo(copy).id, action.id, "fallbackTo mints a new id")
        XCTAssertNotEqual(action.retry(1).id, action.id, "retry mints a new id")
    }

    // MARK: - Helpers

    private func makeSUT(_ work: DMButtonAction.ActionType? = nil) -> CountingAction {
        CountingAction(work ?? succeed)
    }
}
