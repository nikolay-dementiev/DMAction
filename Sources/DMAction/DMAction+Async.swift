//
//  DMAction
//
//  Created by Mykola Dementiev
//

@available(macOS 10.15, *)
public extension DMAction {
    /// Runs the action and waits for its result.
    func runAsync<Output: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        mapSuccess: @escaping @Sendable (any Copyable) throws -> Output
    ) async throws -> DMActionOutcome<Output> {
        throw CancellationError()
    }
}
