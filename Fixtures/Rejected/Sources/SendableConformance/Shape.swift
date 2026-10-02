import DMAction

// Treating an action or its result as Sendable.
func erase(_ action: DMButtonAction, _ result: DMButtonAction.ResultType) -> [any Sendable] {
    [action, result]
}
