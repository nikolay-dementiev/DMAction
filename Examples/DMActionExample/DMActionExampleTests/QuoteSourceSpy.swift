import DMAction
import DMActionExample
import Foundation

/// Records every call and answers at once, or keeps the completion of a fetch when told to.
@MainActor
final class QuoteSourceSpy: QuoteSource {
    /// The `failing` flag of every fetch, in order.
    private(set) var fetches: [Bool] = []
    private(set) var cachedQuoteCalls = 0
    private(set) var heldFetches: [(DMButtonAction.ResultType) -> Void] = []
    var holdsFetches = false
    var cacheFails = false

    func fetchQuote(failing: Bool, completion: @escaping (DMButtonAction.ResultType) -> Void) {
        fetches.append(failing)
        if holdsFetches {
            heldFetches.append(completion)
            return
        }
        completion(failing ? .failure(URLError(.timedOut)) : .success("fresh"))
    }

    func cachedQuote(completion: @escaping (DMButtonAction.ResultType) -> Void) {
        cachedQuoteCalls += 1
        completion(cacheFails ? .failure(URLError(.resourceUnavailable)) : .success("cached"))
    }
}
