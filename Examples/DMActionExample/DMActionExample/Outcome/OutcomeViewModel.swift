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

    /// Fetches a quote, retries a failed fetch twice, and shows the cached quote when all three
    /// attempts have failed.
    package func load() {
        state = .loading
        let failures = failuresBeforeSuccess
        var fetches = 0
        let fetch = DMButtonAction { [source] completion in
            fetches += 1
            source.fetchQuote(failing: fetches <= failures, completion: completion)
        }
        let cached = DMButtonAction { [source] completion in
            source.cachedQuote(completion: completion)
        }
        let fetchOrCached = fetch.retry(2).fallbackTo(cached)
        fetchOrCached { [weak self] result in
            self?.show(result)
        }
    }

    private func show(_ result: DMButtonAction.ResultType) {
        switch result.unwrapValue() {
        case let .success(quote):
            // A run labels every success it delivers, so the count is always there.
            state = .loaded(text: String(describing: quote), failedAttempts: result.attemptCount ?? 0)
        case let .failure(error):
            state = .failed(message: error.localizedDescription)
        }
    }
}
