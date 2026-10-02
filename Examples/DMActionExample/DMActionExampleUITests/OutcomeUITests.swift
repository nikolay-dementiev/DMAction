import XCTest

final class OutcomeUITests: XCTestCase {
    @MainActor
    func test_load_withOneFailureBeforeSuccess_showsTheFreshQuoteAfterOneFailedAttempt() throws {
        let app = makeSUT()

        app.buttons["load-button"].tap()

        let shown = NSPredicate(format: "label CONTAINS %@", "Fresh from the network. Failed attempts before it: 1")
        wait(for: [expectation(for: shown, evaluatedWith: app.staticTexts["outcome"])], timeout: 10)
        try app.performAccessibilityAudit()
    }

    // MARK: - Helpers

    @MainActor
    private func makeSUT() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        return app
    }
}
