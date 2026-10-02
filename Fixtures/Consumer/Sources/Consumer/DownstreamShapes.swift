import DMAction
import SwiftUI

// The shapes the downstream package DMUnLoader uses, read from its sources:
//   - the protocol as a type in signatures and stored properties, optional and not
//   - an enum payload with a default of nil
//   - a closure type that carries two actions
//   - an action built from a method of a main-actor type
//   - an action built from an empty closure, with and without a completion parameter
//   - `simpleAction` handed to a SwiftUI button
//   - in its example app: retry, then a fallback built from a method reference
// If one of them stops compiling here, DMUnLoader stops compiling.

@MainActor
protocol DownstreamManager {
    func hide()
}

enum DownstreamState {
    case failure(error: Error, onRetry: DMAction? = nil)
}

@MainActor
protocol DownstreamProvider {
    associatedtype ErrorView: View
    func errorView(error: Error, onRetry: DMAction?, onClose: DMAction) -> ErrorView
}

struct DownstreamErasedProvider {
    let makeErrorView: (Error, DMAction?, DMAction) -> AnyView
}

struct DownstreamErrorView: View {
    let onRetry: DMAction?
    let onClose: DMAction

    init(onRetry: DMAction? = nil, onClose: DMAction) {
        self.onRetry = onRetry
        self.onClose = onClose
    }

    var body: some View {
        VStack {
            if let onRetry {
                Button("Retry", action: onRetry.simpleAction)
            }
            Button("Close", action: onClose.simpleAction)
        }
    }
}

@MainActor
func downstreamCloseAction<Manager: DownstreamManager>(_ manager: Manager) -> DMAction {
    DMButtonAction(manager.hide)
}

@MainActor
func downstreamPreviewActions() -> [DMAction] {
    [DMButtonAction {}, DMButtonAction({ _ in })]
}

@MainActor
final class DownstreamExampleModel {
    func makeRetryAction() -> DMAction {
        DMButtonAction { [weak self] completion in
            self?.load(completion: completion)
        }
        .retry(2)
        .fallbackTo(DMButtonAction(loadWithSuccess))
    }

    func state(for error: Error) -> DownstreamState {
        .failure(error: error, onRetry: makeRetryAction())
    }

    private func load(completion: @escaping (DMAction.ResultType) -> Void) {
        completion(.failure(ConsumerError()))
    }

    private func loadWithSuccess(completion: @escaping (DMAction.ResultType) -> Void) {
        completion(.success(PlaceholderCopyable()))
    }
}
