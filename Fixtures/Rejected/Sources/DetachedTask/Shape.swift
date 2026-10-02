import DMAction

// Completing from a detached task.
func makeAction() -> DMButtonAction {
    DMButtonAction { completion in
        Task.detached {
            completion(.success("done"))
        }
    }
}
