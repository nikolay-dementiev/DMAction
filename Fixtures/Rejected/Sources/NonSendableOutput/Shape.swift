import DMAction

// The mapped value leaves the wait, so its type has to be Sendable.
// expected-error: does not conform to the 'Sendable' protocol
final class Box {}

func load(_ action: any DMAction) async throws -> Box {
    try await action.runAsync { _ in Box() }.value
}
