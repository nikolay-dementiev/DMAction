import DMAction
import Foundation

// The exact types of the released API. A literal argument or an annotated result still
// compiles after a parameter or a property changes its type. A function value, a key path
// and a generic constraint do not. Nothing here is executed.

/// A third-party result value that reports its own count.
struct ConsumerCountedValue: DMActionResultValueProtocol {
    let attemptCount: UInt?
}

/// Generic code over any action.
func run<Action: DMAction>(_ action: Action, completion: @escaping (Action.ResultType) -> Void) {
    action(completion: completion)
}

/// An action behind an opaque type.
func opaqueAction() -> some DMAction {
    DMButtonAction(produceValue)
}

func exactRequirementTypes<Action: DMAction, Value: DMActionResultValueProtocol>(
    of _: Action.Type,
    and _: Value.Type
) {
    let attempt: KeyPath<Action, UInt> = \.currentAttempt
    let identifier: KeyPath<Action, UUID> = \.id
    let work: KeyPath<Action, Action.ActionType> = \.action
    let ignoringResult: KeyPath<Action, () -> Void> = \.simpleAction
    let count: KeyPath<Value, UInt?> = \.attemptCount
    _ = (attempt, identifier, work, ignoringResult, count)
}

func exactPropertyTypes() {
    let count: KeyPath<DMActionResultValue, UInt?> = \.attemptCount
    let payload: KeyPath<DMActionResultValue, any Copyable> = \.value
    let resultCount: KeyPath<DMButtonAction.ResultType, UInt?> = \.attemptCount
    _ = (count, payload, resultCount)
}

func exactAliases() {
    let result: (DMButtonAction.ResultType) -> Result<any Copyable, any Error> = { $0 }
    let work: (@escaping DMButtonAction.ActionType)
        -> (@escaping (Result<any Copyable, any Error>) -> Void) -> Void = { $0 }
    _ = (result, work)
}

func exactFunctionTypes(of action: DMButtonAction) {
    let retry: (UInt) -> any DMAction = action.retry
    let fallbackTo: (any DMAction) -> DMActionWithFallback = action.fallbackTo
    let call: (@escaping (DMButtonAction.ResultType) -> Void) -> Void = action.callAsFunction(completion:)
    let makeFromResult: (@escaping DMButtonAction.ActionType) -> DMButtonAction = DMButtonAction.init
    let makeFromClosure: (@escaping () -> Void) -> DMButtonAction = DMButtonAction.init
    let makeFallback: (UInt, @escaping DMButtonAction.ActionType, @escaping DMButtonAction.ActionType)
        -> DMActionWithFallback = DMActionWithFallback.init(currentAttempt:_:_:)
    let makeValue: (any Copyable, UInt?) -> DMActionResultValue = DMActionResultValue.init(value:attemptCount:)
    let makePlaceholder: () -> PlaceholderCopyable = PlaceholderCopyable.init
    _ = (retry, fallbackTo, call, makeFromResult, makeFromClosure, makeFallback, makeValue, makePlaceholder)
}

/// Every kind of action can be retried, given as a fallback and run by generic code.
func everyKindOfOperand(_ button: DMButtonAction, _ composed: DMActionWithFallback, _ custom: ConsumerAction) {
    let count: UInt = 2
    let erased: any DMAction = button.retry(count)
    let optional: (any DMAction)? = erased
    _ = button.fallbackTo(composed)
    _ = button.fallbackTo(custom)
    _ = button.fallbackTo(erased)
    _ = erased.fallbackTo(opaqueAction())
    _ = composed.retry(count).fallbackTo(custom.retry(count))
    run(custom) { _ in }
    run(composed) { _ in }
    optional?.simpleAction()
}

func exactConformances() {
    let values: [any DMActionResultValueProtocol] = [
        DMActionResultValue(value: "payload"),
        ConsumerCountedValue(attemptCount: 4),
        ConsumerValue(text: "text")
    ]
    let actions: [any DMAction] = [DMButtonAction(produceValue), opaqueAction()]
    let payload: any Copyable = PlaceholderCopyable()
    _ = (values, actions, payload)
}
