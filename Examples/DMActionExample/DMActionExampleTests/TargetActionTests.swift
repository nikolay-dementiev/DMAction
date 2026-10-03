import DMAction
import UIKit
import XCTest

/// A control hands its touch to an action through UIKit's target-action machinery. The test
/// lives with the example, where the package meets UIKit; it does not need an app host.
final class TargetActionTests: XCTestCase {
    /// Counts how often the action ran.
    @MainActor
    private final class Runs {
        var count = 0
    }

    @MainActor
    func test_simpleAction_whenAButtonSendsItsTouchUpInside_runsTheActionOnce() {
        let (button, runs) = makeSUT()

        button.sendActions(for: .touchUpInside)

        XCTAssertEqual(runs.count, 1)
    }

    // MARK: - Helpers

    @MainActor
    private func makeSUT() -> (button: UIButton, runs: Runs) {
        let runs = Runs()
        let action = DMButtonAction {
            runs.count += 1
        }
        let button = UIButton(type: .system)
        button.addAction(UIAction { _ in action.simpleAction() }, for: .touchUpInside)
        return (button, runs)
    }
}
