import DMAction
import os
import OSLog
import XCTest

/// The public entry points report to the signposts of the system, in the subsystem and category
/// that the documentation names. The test reads them back from the log of its own process.
final class SystemSignpostTests: XCTestCase {
    func test_publicEntryPoints_writeTheSignpostsOfEachRunToTheSystem() async throws {
        let marker = UUID().uuidString
        let markers = Logger(subsystem: "DMActionTests", category: "SystemSignpostTests")
        let sut = makeSUT()

        markers.notice("start \(marker, privacy: .public)")
        sut { _ in }
        sut.action { _ in }
        _ = try await sut.runAsync { _ in true }
        markers.notice("end \(marker, privacy: .public)")

        let signposts = try signposts(between: "start \(marker)", and: "end \(marker)")
        let intervals = signposts.map { "\($0.signpostName) \(Self.kind(of: $0))" }
        let oneRun = ["run begin", "attempt begin", "attempt end", "run end"]
        XCTAssertEqual(
            intervals, oneRun + oneRun + oneRun,
            "call syntax, the action and the async surface each report one run"
        )
        XCTAssertEqual(Set(signposts.map(\.category)), ["ActionRun"], "in the category the documentation names")
    }

    // MARK: - Helpers

    private func makeSUT() -> DMButtonAction {
        DMButtonAction { completion in completion(.success("value")) }
    }

    /// The signposts of subsystem DMAction that were written between the two log lines.
    private func signposts(between start: String, and end: String) throws -> [OSLogEntrySignpost] {
        // An entry may reach the store a moment after it was written: read until the end marker
        // is there, three reads at most.
        var entries: [OSLogEntry] = []
        for _ in 0..<3 {
            entries = Array(
                try OSLogStore(scope: .currentProcessIdentifier)
                    .getEntries(matching: NSPredicate(format: "subsystem IN %@", ["DMAction", "DMActionTests"]))
            )
            if entries.contains(where: { $0.composedMessage == end }) {
                break
            }
        }
        let first = try XCTUnwrap(entries.firstIndex { $0.composedMessage == start }, "the start marker")
        let last = try XCTUnwrap(entries.firstIndex { $0.composedMessage == end }, "the end marker")
        return entries[first..<last].compactMap { $0 as? OSLogEntrySignpost }.filter { $0.subsystem == "DMAction" }
    }

    private static func kind(of signpost: OSLogEntrySignpost) -> String {
        switch signpost.signpostType {
        case .intervalBegin: "begin"
        case .intervalEnd: "end"
        case .event: "event"
        case .undefined: "undefined"
        @unknown default: "unknown"
        }
    }
}
