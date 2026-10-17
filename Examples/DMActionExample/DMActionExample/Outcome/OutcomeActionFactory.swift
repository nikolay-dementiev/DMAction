import DMAction

/// Builds the action that one load of the outcome screen runs.
@MainActor
package protocol OutcomeActionFactory {
    /// The action for one load, a new one for every request: the default one counts its fetches
    /// inside it. `failures` is how many fetches fail before one succeeds.
    func makeAction(failingFetches failures: Int) -> any DMAction
}

/// Fetches a quote, retries a failed fetch twice, and falls back to the cached quote when all
/// three attempts have failed.
@MainActor
package struct DefaultOutcomeActionFactory: OutcomeActionFactory {
    private let source: any QuoteSource

    package init(source: any QuoteSource) {
        self.source = source
    }

    package func makeAction(failingFetches failures: Int) -> any DMAction {
        var fetches = 0
        let fetch = DMButtonAction { [source] completion in
            fetches += 1
            source.fetchQuote(failing: fetches <= failures, completion: completion)
        }
        let cached = DMButtonAction { [source] completion in
            source.cachedQuote(completion: completion)
        }
        return fetch.retry(2).fallbackTo(cached)
    }
}
