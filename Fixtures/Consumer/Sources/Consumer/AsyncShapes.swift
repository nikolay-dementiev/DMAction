import DMAction

// Uses of the async surface from the three kinds of caller. They compile in Swift 6 mode and have
// to keep compiling: a main-actor type and a custom actor that run actions they own, and a
// nonisolated async function. Where one of them runs an action twice, the action is still usable
// after the first await.

@MainActor
final class AsyncModel {
    private(set) var text = ""
    private(set) var attempts: UInt = 0

    func load(_ action: DMAction) async throws {
        let outcome = try await action.runAsync { payload in "\(payload)" }
        text = outcome.value
        attempts = outcome.attemptCount
    }

    func loadTwice() async throws -> String {
        let action = makeAction()
        _ = try await action.runAsync { _ in () }
        return try await action.runAsync { payload in "\(payload)" }.value
    }

    private func makeAction() -> DMButtonAction {
        DMButtonAction { [text] completion in completion(.success(text)) }
    }
}

actor AsyncStore {
    private var last = ""

    func load(_ action: DMAction) async throws -> UInt {
        let outcome = try await action.runAsync { payload in "\(payload)" }
        last = outcome.value
        return outcome.attemptCount
    }

    func keep(_ outcome: DMActionOutcome<String>) {
        last = outcome.value
    }
}

private enum ShapeError: Error {
    case notText
}

func nonisolatedCaller() async throws -> String {
    let action = DMButtonAction { completion in completion(.success("value")) }
    let text = try await action.runAsync { payload in "\(payload)" }
    let number = try await action.runAsync { _ in 42 }
    let nothing: DMActionOutcome<Void> = try await action.runAsync { _ in () }
    _ = nothing.attemptCount
    return text.value + String(number.value)
}

func nonisolatedCallerOfAComposition(_ make: () -> DMAction) async throws -> UInt {
    let composed = make().retry(2)
    let outcome = try await composed.runAsync { payload -> String in
        guard let text = payload as? String else {
            throw ShapeError.notText
        }
        return text
    }
    return outcome.attemptCount
}

func transfer(_ outcome: DMActionOutcome<String>, to store: AsyncStore) async {
    await store.keep(outcome)
}
