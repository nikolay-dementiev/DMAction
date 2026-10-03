import DMAction

// Completing from a detached task.
// expected-error: passing closure as a 'sending' parameter risks causing data races
func makeAction() -> DMButtonAction {
    DMButtonAction { completion in
        Task.detached {
            completion(.success("done"))
        }
    }
}
