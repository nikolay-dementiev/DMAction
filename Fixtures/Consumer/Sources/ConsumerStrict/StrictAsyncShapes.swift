import DMAction
import Foundation

// The async surface under ExistentialAny, which this target turns on: an existential, a generic, an
// opaque and a concrete receiver, a main-actor caller, and a conformer that already has a member
// named runAsync. They compile in Swift 6 mode without a warning and have to keep compiling.

func existentialReceiver(_ action: any DMAction) async throws -> UInt {
    try await action.runAsync { "\($0)" }.attemptCount
}

func genericReceiver<Action: DMAction>(_ action: Action) async throws -> String {
    try await action.runAsync { "\($0)" }.value
}

func opaqueReceiver(_ action: some DMAction) async throws -> String {
    try await action.runAsync { "\($0)" }.value
}

func concreteReceiver() async throws -> UInt {
    let button = DMButtonAction { $0(.success("v")) }
    let composed = button.fallbackTo(DMButtonAction { $0(.success("w")) })
    return try await composed.runAsync { _ in () }.attemptCount
}

@MainActor
func mainActorCaller(_ action: any DMAction) async throws -> String {
    let first = try await action.runAsync { "\($0)" }
    let second = try await action.runAsync { "\($0)" }
    return first.value + second.value
}

/// A conformer that has a `runAsync` of its own: a call on the concrete type finds that member, a
/// call through the protocol finds the one of the library.
struct OwnRunner: DMAction {
    let currentAttempt: UInt = 0
    let id = UUID()
    let action: ActionType = { $0(.success("own")) }

    func runAsync(mapSuccess: @escaping @Sendable (any Copyable) throws -> String) async throws -> String {
        "own"
    }
}

func lookupPrefersTheMemberOfTheConformer() async throws -> (String, DMActionOutcome<String>) {
    let own = OwnRunner()
    let throughTheType: String = try await own.runAsync { _ in "x" }
    let throughTheProtocol: DMActionOutcome<String> = try await (own as any DMAction).runAsync { _ in "x" }
    return (throughTheType, throughTheProtocol)
}
