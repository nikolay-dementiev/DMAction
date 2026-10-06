import Foundation
import XCTest

/// Runs an accessibility audit again when the audit throws its own timeout.
///
/// Hosted runners sometimes see the audit give up with "Audit failed to complete in time"
/// (domain `com.apple.xcode.xctest.accessibilityAudit`, code -56) before it has checked
/// anything, and the next run completes. Any other error is thrown at once. An issue the
/// audit reports is not an error: it goes through the audit's issue handler, and that is
/// no reason to run the audit again. Each timeout that is run again is recorded as an activity
/// of the test, so a passing run still shows it in the result bundle.
struct AccessibilityAuditRetry {
    /// The first run and at most two more, so an audit that times out every time still ends.
    static let attemptLimit = 3

    func perform(_ audit: () throws -> Void) throws {
        for attempt in 1..<Self.attemptLimit {
            do {
                try audit()
                return
            } catch let error as NSError where Self.isAuditTimeout(error) {
                XCTContext.runActivity(
                    named: "Accessibility audit attempt \(attempt) of \(Self.attemptLimit) timed out; running it again"
                ) { _ in }
            }
        }
        try audit()
    }

    private static func isAuditTimeout(_ error: NSError) -> Bool {
        error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
    }
}
