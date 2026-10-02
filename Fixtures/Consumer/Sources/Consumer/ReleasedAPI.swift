import DMAction
import Foundation

// Every public declaration of DMAction 1.0.5, written the way a consumer writes it.
// Nothing here is executed. The file is compiled by Scripts/check-manifest.sh: a renamed
// symbol, a removed default value or a changed argument label stops it from building.

struct ConsumerError: Error {}

/// A third-party conformer: the three stored requirements and the default `simpleAction`.
struct ConsumerAction: DMAction {
    let currentAttempt: UInt = 0
    let id = UUID()
    let action: ActionType
}

/// A third-party conformer that supplies its own `simpleAction`.
struct ConsumerSilentAction: DMAction {
    let currentAttempt: UInt = 0
    let id = UUID()
    let action: ActionType
    let simpleAction: () -> Void
}

/// A third-party result value that relies on the default `attemptCount`.
struct ConsumerValue: DMActionResultValueProtocol {
    let text: String
}

func produceValue(completion: @escaping (DMAction.ResultType) -> Void) {
    completion(.success("value"))
}

struct ReleasedActions {
    let withResult: DMButtonAction
    let simple: DMButtonAction
    let fromFunction: DMButtonAction
}

func releasedInitializers() -> ReleasedActions {
    let withResult = DMButtonAction { completion in
        completion(.failure(ConsumerError()))
    }
    let simple = DMButtonAction {
        // A closure with no result: the action always succeeds.
    }
    let fromFunction = DMButtonAction(produceValue)
    return ReleasedActions(withResult: withResult, simple: simple, fromFunction: fromFunction)
}

func releasedRequirements(of action: DMButtonAction, and composed: DMActionWithFallback) {
    let attempt: UInt = action.currentAttempt
    let identifier: UUID = action.id
    let work: DMButtonAction.ActionType = action.action
    let ignoringResult: () -> Void = action.simpleAction
    let composedAttempt: UInt = composed.currentAttempt
    let composedIdentifier: UUID = composed.id
    let composedWork: DMActionWithFallback.ActionType = composed.action
    _ = (attempt, identifier, work, ignoringResult, composedAttempt, composedIdentifier, composedWork)
}

func releasedComposition() {
    let actions = releasedInitializers()
    let withResult = actions.withResult
    let simple = actions.simple
    let fromFunction = actions.fromFunction

    let retried: DMAction = withResult.retry(2)
    let withFallback: DMActionWithFallback = withResult.fallbackTo(simple)
    let chain: DMActionWithFallback = withResult.retry(1).fallbackTo(fromFunction)
    let direct = DMActionWithFallback(currentAttempt: 1, withResult.action, simple.action)
    releasedRequirements(of: withResult, and: direct)

    withResult.simpleAction()
    withFallback.action { _ in }
    retried(completion: { _ in })
    chain.callAsFunction(completion: { _ in })
    chain { result in
        let attempts: UInt? = result.attemptCount
        let unwrapped: DMAction.ResultType = result.unwrapValue()
        switch unwrapped {
        case .success(let value):
            _ = (value as? String, attempts)
        case .failure(let error):
            _ = error
        }
    }
}

func releasedValues() {
    let wrapped = DMActionResultValue(value: "payload")
    let counted = DMActionResultValue(value: PlaceholderCopyable(), attemptCount: 3)
    let count: UInt? = wrapped.attemptCount
    let payload: Copyable = counted.value
    let defaultCount: UInt? = ConsumerValue(text: "text").attemptCount

    let result: Result<Copyable, Error> = .success(counted)
    let sameResult: DMAction.ResultType = result.unwrapValue()
    let resultCount: UInt? = result.attemptCount
    let work: DMAction.ActionType = { completion in
        completion(.failure(ConsumerError()))
    }
    _ = (count, payload, defaultCount, sameResult, resultCount, work)
}

func releasedConformers() {
    let custom = ConsumerAction(action: produceValue)
    custom.simpleAction()
    custom { _ in }
    _ = custom.retry(1)
    _ = custom.fallbackTo(DMButtonAction(produceValue))

    let silent = ConsumerSilentAction(action: produceValue, simpleAction: {})
    silent.simpleAction()
}
