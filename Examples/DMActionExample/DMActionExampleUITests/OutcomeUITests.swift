import XCTest

final class OutcomeUITests: XCTestCase {
    @MainActor
    func test_launch_passesEveryAccessibilityAudit() throws {
        let app = makeSUT()

        try app.performAccessibilityAudit()
    }

    @MainActor
    func test_load_withOneFailureBeforeSuccess_showsTheFreshQuoteAfterOneFailedAttempt() throws {
        let app = makeSUT()

        app.buttons["load-button"].tap()

        let shown = NSPredicate(format: "label CONTAINS %@", "Fresh from the network. Failed attempts before it: 1")
        wait(for: [expectation(for: shown, evaluatedWith: app.staticTexts["outcome"])], timeout: 10)
        // At the largest text sizes the longer outcome pushes the footer out of view, and the audit
        // reports a text it cannot see as not scaling, whatever its font. Dynamic Type is audited
        // at launch instead, where every text stays in view.
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType))
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
