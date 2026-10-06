import Foundation
import XCTest

final class AccessibilityAuditRetryTests: XCTestCase {
    @MainActor
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

    @MainActor
    func test_perform_whenEveryRunTimesOut_throwsTheLastTimeoutAfterThreeRuns() {
        let sut = makeSUT()
        var runs = 0

        XCTAssertThrowsError(try sut.perform {
            runs += 1
            throw auditTimeout(run: runs)
        }, "three runs time out, and the call throws") { error in
            XCTAssertEqual((error as NSError).userInfo["run"] as? Int, 3, "the error thrown is the one of the third run")
        }
        XCTAssertEqual(runs, 3, "three runs in all, and then the timeout is thrown")
    }

    @MainActor
    func test_perform_whenTheAuditFailsWithAnotherError_throwsItAfterOneRun() {
        let sut = makeSUT()
        var runs = 0

        XCTAssertThrowsError(try sut.perform {
            runs += 1
            throw OtherAuditFailure()
        }, "an error that is not a timeout is thrown") { error in
            XCTAssertEqual(error as? OtherAuditFailure, OtherAuditFailure(), "the error is thrown as it is")
        }
        XCTAssertEqual(runs, 1, "an error that is not a timeout is not run again")
    }

    @MainActor
    func test_perform_whenTheErrorHasTheTimeoutCodeInAnotherDomain_throwsItAfterOneRun() {
        let sut = makeSUT()
        var runs = 0

        XCTAssertThrowsError(try sut.perform {
            runs += 1
            throw NSError(domain: "DMActionExampleUITests.Other", code: -56)
        }, "a code of -56 in another domain is thrown at once") { error in
            XCTAssertEqual((error as NSError).domain, "DMActionExampleUITests.Other", "the error is thrown as it is")
        }
        XCTAssertEqual(runs, 1, "the domain is part of the check: an error of another domain is not run again")
    }

    @MainActor
    func test_perform_whenTheAuditDomainHasAnotherCode_throwsItAfterOneRun() {
        let sut = makeSUT()
        var runs = 0

        XCTAssertThrowsError(try sut.perform {
            runs += 1
            throw NSError(domain: "com.apple.xcode.xctest.accessibilityAudit", code: -57)
        }, "an audit error with another code is thrown at once") { error in
            XCTAssertEqual((error as NSError).code, -57, "the error is thrown as it is")
        }
        XCTAssertEqual(runs, 1, "the code is part of the check: an audit error with another code is not run again")
    }

    @MainActor
    func test_perform_whenTheAuditReturns_runsItOnce() throws {
        let sut = makeSUT()
        var runs = 0

        try sut.perform {
            runs += 1
        }

        XCTAssertEqual(runs, 1, "an audit that returns is not run again")
    }

    // MARK: - Helpers

    @MainActor
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
