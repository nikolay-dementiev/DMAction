import DMAction

// Uses of DMAction inside one isolation domain. They compile in Swift 6 mode today and
// have to keep compiling: a main-actor type that runs an action, builds one from its own
// method, and completes one from a task it creates.

@MainActor
final class IsolatedModel {
    private(set) var text = ""

    func run(_ action: DMAction) {
        action { [weak self] result in
            self?.text = "\(result)"
        }
    }

    func makeAction() -> DMButtonAction {
        DMButtonAction(work)
    }

    func makeTaskAction() -> DMButtonAction {
        DMButtonAction { completion in
            Task {
                await Task.yield()
                completion(.success("done"))
            }
        }
    }

    private func work(completion: @escaping (DMAction.ResultType) -> Void) {
        completion(.success(text))
    }
}
