import DMAction

// Treating the result of an action as Sendable.
// expected-error: type 'any Copyable' does not conform to the 'Sendable' protocol
func erase(_ result: DMButtonAction.ResultType) -> any Sendable {
    result
}
