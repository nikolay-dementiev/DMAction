import DMAction

// Completing from an unstructured task that was created in a nonisolated closure.
func makeAction() -> DMButtonAction {
    DMButtonAction { completion in
        Task {
            completion(.success("done"))
        }
    }
}
