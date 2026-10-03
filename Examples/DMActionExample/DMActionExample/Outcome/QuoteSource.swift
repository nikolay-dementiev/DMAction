import DMAction
import Foundation

/// Where the example's quotes come from.
///
/// Call the completions on the main actor. A composed action goes on with its run on the thread
/// of a completion, and the view model that runs it keeps its state on the main actor.
@MainActor
package protocol QuoteSource {
    /// Fetches a quote. `failing` makes this one call fail, so that the example can show a retry
    /// and a fallback whenever the user asks for them.
    func fetchQuote(failing: Bool, completion: @escaping (DMButtonAction.ResultType) -> Void)

    /// The quote kept from an earlier visit, for when every fetch has failed.
    func cachedQuote(completion: @escaping (DMButtonAction.ResultType) -> Void)
}

/// Answers after a short delay, the way a network does.
@MainActor
package final class SimulatedQuoteSource: QuoteSource {
    private let delay: Duration

    package init(delay: Duration = .milliseconds(300)) {
        self.delay = delay
    }

    package func fetchQuote(failing: Bool, completion: @escaping (DMButtonAction.ResultType) -> Void) {
        Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                completion(.failure(error))
                return
            }
            completion(failing ? .failure(URLError(.timedOut)) : .success("Fresh from the network"))
        }
    }

    package func cachedQuote(completion: @escaping (DMButtonAction.ResultType) -> Void) {
        completion(.success("Kept from the last visit"))
    }
}
