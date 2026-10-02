import DMAction

// Bridging an action to async code: the result cannot be sent out of the completion.
func value(of action: any DMAction) async -> DMButtonAction.ResultType {
    await withCheckedContinuation { continuation in
        action { result in
            continuation.resume(returning: result)
        }
    }
}
