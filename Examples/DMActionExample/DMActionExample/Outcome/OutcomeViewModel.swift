import DMAction
import Observation

/// What the outcome screen shows.
package enum OutcomeState: Equatable {
    case idle
    case loading
    case loaded(text: String, failedAttempts: UInt)
    case failed(message: String)
}

/// The state and the decisions of the outcome screen.
@MainActor
package protocol OutcomeViewModel: AnyObject, Observable {
    /// How many fetches fail before one succeeds. From three on, the fetch and its two retries
    /// all fail and the cached quote is shown.
    var failuresBeforeSuccess: Int { get set }
    var state: OutcomeState { get }
    func load()
}

@MainActor
@Observable
package final class DefaultOutcomeViewModel: OutcomeViewModel {
    package var failuresBeforeSuccess = 1
    package private(set) var state = OutcomeState.idle
    private let source: any QuoteSource

    package init(source: any QuoteSource) {
        self.source = source
    }

    package func load() {
        state = .loading
    }
}
