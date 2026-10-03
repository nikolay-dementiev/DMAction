import DMAction

// Completing from an unstructured task that was created in a nonisolated closure.
// expected-error: passing closure as a 'sending' parameter risks causing data races
func makeAction() -> DMButtonAction {
    DMButtonAction { completion in
        Task {
            completion(.success("done"))
        }
    }
}
