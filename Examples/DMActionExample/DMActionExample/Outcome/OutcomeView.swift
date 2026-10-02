import SwiftUI

/// What came back, how many fetches fail, and a button that loads.
///
/// The outcome comes first, so that it stays in view at the largest text sizes.
/// The header and the footer use the primary color: their default gray reaches only about 3.3:1
/// on the grouped background, under the 4.5:1 that text needs. It is the color `Color.primary`,
/// because the hierarchical `.primary` resolves to that gray inside a header or a footer.
struct OutcomeView<ViewModel: OutcomeViewModel>: View {
    @Bindable var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    outcome
                } header: {
                    Text("Outcome")
                        .foregroundStyle(Color.primary)
                }
                Section {
                    Stepper(value: $viewModel.failuresBeforeSuccess, in: 0...4) {
                        Text("Failures before success: \(viewModel.failuresBeforeSuccess)")
                    }
                    .accessibilityIdentifier("failures-stepper")
                    Button("Load") {
                        viewModel.load()
                    }
                    .disabled(viewModel.state == .loading)
                    .accessibilityIdentifier("load-button")
                } footer: {
                    Text("The fetch is retried twice. When all three attempts fail, the cached quote is shown.")
                        .foregroundStyle(Color.primary)
                }
            }
            .navigationTitle("DMAction")
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch viewModel.state {
        case .idle:
            Text("Nothing loaded yet")
                .accessibilityIdentifier("outcome")
        case .loading:
            ProgressView("Loading")
                .accessibilityIdentifier("outcome")
        case let .loaded(text, failedAttempts):
            Text("\(text). Failed attempts before it: \(failedAttempts)")
                .accessibilityIdentifier("outcome")
        case let .failed(message):
            // Red text on a white row reaches only about 3.5:1, so the red goes on the icon.
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("outcome")
        }
    }
}

// MARK: - Previews

#Preview("Idle") {
    OutcomeView(viewModel: PreviewOutcomeViewModel(state: .idle))
}

#Preview("Loading") {
    OutcomeView(viewModel: PreviewOutcomeViewModel(state: .loading))
}

#Preview("Loaded after one failed attempt") {
    OutcomeView(viewModel: PreviewOutcomeViewModel(state: .loaded(text: "Fresh from the network", failedAttempts: 1)))
}

#Preview("Loaded from the cache") {
    OutcomeView(viewModel: PreviewOutcomeViewModel(state: .loaded(text: "Kept from the last visit", failedAttempts: 3)))
}

#Preview("Failed") {
    OutcomeView(viewModel: PreviewOutcomeViewModel(state: .failed(message: "The request timed out.")))
}

/// A view model that shows one state and does nothing.
@MainActor
@Observable
private final class PreviewOutcomeViewModel: OutcomeViewModel {
    var failuresBeforeSuccess = 1
    let state: OutcomeState

    init(state: OutcomeState) {
        self.state = state
    }

    func load() {}
}
