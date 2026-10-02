import DMActionExample
import Foundation
import XCTest

final class DefaultOutcomeViewModelTests: XCTestCase {
    @MainActor
    func test_state_beforeTheFirstLoad_isIdle() {
        let (viewModel, _) = makeSUT()

        XCTAssertEqual(viewModel.state, .idle)
    }

    @MainActor
    func test_load_whileTheFetchIsOutstanding_isLoading() {
        let (viewModel, source) = makeSUT()
        source.holdsFetches = true

        viewModel.load()

        XCTAssertEqual(viewModel.state, .loading)
    }

    @MainActor
    func test_load_whenTheFirstFetchSucceeds_showsTheFreshQuoteWithNoFailedAttempt() {
        let (viewModel, source) = makeSUT(failuresBeforeSuccess: 0)

        viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded(text: "fresh", failedAttempts: 0), "the fresh quote, first try")
        XCTAssertEqual(source.fetches, [false], "one fetch")
        XCTAssertEqual(source.cachedQuoteCalls, 0, "no fallback")
    }

    @MainActor
    func test_load_whenTwoFetchesFail_retriesAndShowsTheFreshQuoteAfterTwoFailedAttempts() {
        let (viewModel, source) = makeSUT(failuresBeforeSuccess: 2)

        viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded(text: "fresh", failedAttempts: 2), "the fresh quote of the third fetch")
        XCTAssertEqual(source.fetches, [true, true, false], "the fetch and two retries")
        XCTAssertEqual(source.cachedQuoteCalls, 0, "no fallback")
    }

    @MainActor
    func test_load_whenEveryFetchFails_showsTheCachedQuoteAfterThreeFailedAttempts() {
        let (viewModel, source) = makeSUT(failuresBeforeSuccess: 3)

        viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded(text: "cached", failedAttempts: 3), "the fallback's quote")
        XCTAssertEqual(source.fetches, [true, true, true], "the fetch and two retries, all failed")
        XCTAssertEqual(source.cachedQuoteCalls, 1, "the fallback ran once")
    }

    @MainActor
    func test_load_whenTheCacheFailsToo_showsTheErrorOfTheCache() {
        let (viewModel, source) = makeSUT(failuresBeforeSuccess: 4)
        source.cacheFails = true

        viewModel.load()

        XCTAssertEqual(viewModel.state, .failed(message: URLError(.resourceUnavailable).localizedDescription))
    }

    // MARK: - Transitions

    @MainActor
    func test_load_whileLoading_startsNoSecondRun() {
        let (viewModel, source) = makeSUT(failuresBeforeSuccess: 0)
        source.holdsFetches = true

        viewModel.load()
        viewModel.load()
        source.heldFetches.first?(.success("fresh"))

        XCTAssertEqual(source.fetches, [false], "one fetch: a load while loading starts nothing")
        XCTAssertEqual(viewModel.state, .loaded(text: "fresh", failedAttempts: 0), "the first run's quote")
    }

    @MainActor
    func test_load_afterAQuoteWasShown_loadsAgain() {
        let (viewModel, source) = makeSUT(failuresBeforeSuccess: 0)
        viewModel.load()
        source.holdsFetches = true

        viewModel.load()

        XCTAssertEqual(viewModel.state, .loading, "loading again")
        XCTAssertEqual(source.fetches, [false, false], "a fetch for each load")
    }

    @MainActor
    func test_load_afterAFailure_loadsAgain() {
        let (viewModel, source) = makeSUT(failuresBeforeSuccess: 4)
        source.cacheFails = true
        viewModel.load()
        source.holdsFetches = true

        viewModel.load()

        XCTAssertEqual(viewModel.state, .loading, "loading again")
        XCTAssertEqual(source.fetches.count, 4, "the three fetches of the first load and one of the second")
    }

    // MARK: - Helpers

    @MainActor
    private func makeSUT(failuresBeforeSuccess: Int = 1) -> (viewModel: DefaultOutcomeViewModel, source: QuoteSourceSpy) {
        let source = QuoteSourceSpy()
        let viewModel = DefaultOutcomeViewModel(source: source)
        viewModel.failuresBeforeSuccess = failuresBeforeSuccess
        return (viewModel, source)
    }
}
