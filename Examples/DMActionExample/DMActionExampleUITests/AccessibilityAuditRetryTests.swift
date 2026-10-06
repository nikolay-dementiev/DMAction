import Foundation
import XCTest

final class AccessibilityAuditRetryTests: XCTestCase {
    func test_perform_whenTheAuditTimesOutTwiceThenPasses_runsItThreeTimes() throws {
        let sut = makeSUT()
        var runs = 0

        try sut.perform {
            runs += 1
            if runs < 3 {
                throw auditTimeout(run: runs)
            }
        }

        XCTAssertEqual(runs, 3, "two timeouts are run again, and the third run passes")
    }

    func test_perform_whenEveryRunTimesOut_throwsTheLastTimeoutAfterThreeRuns() {
        let sut = makeSUT()
        var runs = 0

        XCTAssertThrowsError(try sut.perform {
            runs += 1
            throw auditTimeout(run: runs)
        }) { error in
            XCTAssertEqual((error as NSError).userInfo["run"] as? Int, 3, "the timeout of the third run is the one thrown")
        }
        XCTAssertEqual(runs, 3, "three runs in all, and then the timeout is thrown")
    }

    func test_perform_whenTheAuditFailsWithAnotherError_throwsItAfterOneRun() {
        let sut = makeSUT()
        var runs = 0

        XCTAssertThrowsError(try sut.perform {
            runs += 1
            throw OtherAuditFailure()
        }) { error in
            XCTAssertEqual(error as? OtherAuditFailure, OtherAuditFailure(), "the error is thrown as it is")
        }
        XCTAssertEqual(runs, 1, "an error that is not a timeout is not run again")
    }

    func test_perform_whenTheAuditReturns_runsItOnce() throws {
        let sut = makeSUT()
        var runs = 0

        try sut.perform {
            runs += 1
        }

        XCTAssertEqual(runs, 1, "an audit that returns, with or without the issues it reported, is not run again")
    }

    // MARK: - Helpers

    private func makeSUT() -> AccessibilityAuditRetry {
        AccessibilityAuditRetry()
    }

    private func auditTimeout(run: Int) -> NSError {
        NSError(
            domain: "com.apple.xcode.xctest.accessibilityAudit",
            code: -56,
            userInfo: [NSLocalizedDescriptionKey: "Audit failed to complete in time", "run": run]
        )
    }
}

private struct OtherAuditFailure: Error, Equatable {}
