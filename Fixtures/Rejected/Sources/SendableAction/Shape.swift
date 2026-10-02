import DMAction

// Treating an action as Sendable.
// expected-error: type 'DMButtonAction' does not conform to the 'Sendable' protocol
func erase(_ action: DMButtonAction) -> any Sendable {
    action
}
