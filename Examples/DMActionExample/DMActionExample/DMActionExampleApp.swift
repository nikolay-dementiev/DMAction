import SwiftUI

/// The composition root: the only place that names the concrete source, action factory and view model.
@main
struct DMActionExampleApp: App {
    @State private var viewModel = DefaultOutcomeViewModel(
        actions: DefaultOutcomeActionFactory(source: SimulatedQuoteSource())
    )

    var body: some Scene {
        WindowGroup {
            OutcomeView(viewModel: viewModel)
        }
    }
}
