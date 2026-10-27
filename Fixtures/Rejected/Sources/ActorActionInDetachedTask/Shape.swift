import DMAction

// An action that an actor owns cannot be run from a detached task: the action is not Sendable.
// expected-error: passing closure as a 'sending' parameter risks causing data races
actor Owner {
    private let action = DMButtonAction { completion in completion(.success("v")) }

    func start() {
        let action = action
        Task.detached {
            _ = try await action.runAsync { payload in "\(payload)" }
        }
    }
}
