import DMAction

// The mapper runs on the thread of the callback, so it may not capture a mutable reference.
// expected-error: type 'Tally' in a
final class Tally {
    var count = 0
}

func load(_ action: any DMAction) async throws -> String {
    let tally = Tally()
    return try await action.runAsync { payload in
        tally.count += 1
        return "\(payload)"
    }.value
}
