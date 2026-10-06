/// Runs an accessibility audit once.
struct AccessibilityAuditRetry {
    func perform(_ audit: () throws -> Void) throws {
        try audit()
    }
}
