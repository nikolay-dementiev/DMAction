//
//  DMAction
//
//  Created by Mykola Dementiev
//

@available(macOS 10.15, *)
public extension DMAction {
    /// Runs the action as a guarded run, waits for its result and returns it mapped.
    ///
    /// The run is the one ``callAsFunction(completion:)`` starts, whatever the conformer is, so
    /// a completion that a third-party producer calls twice is ignored. The first producer runs
    /// on the calling thread before this suspends. A caller that is isolated to an actor keeps
    /// that isolation: pass nothing for `isolation`.
    ///
    /// `mapSuccess` receives the payload of the success, unwrapped. It runs where the completion
    /// arrives, which can be any thread, before the result reaches the waiting caller, so it must
    /// be a quick, pure mapping into a `Sendable` value. If it throws, this throws that error and
    /// no retry or fallback starts.
    ///
    /// ```swift
    /// import DMAction
    ///
    /// let greeting = DMButtonAction { completion in completion(.success("Hello")) }
    /// let outcome = try await greeting.runAsync { payload in "\(payload), world" }
    /// print(outcome.value, outcome.attemptCount) // Hello, world 0
    /// ```
    ///
    /// ## Cancellation
    ///
    /// Cancelling the task ends the wait and nothing else.
    ///
    /// - A task that is cancelled when this is called throws `CancellationError` at once and
    ///   starts no producer.
    /// - The wait ends with the first of two events: the mapped result, or the cancellation. A
    ///   cancellation that arrives while `mapSuccess` runs wins, and the mapped value is dropped.
    /// - A completion that arrives after the wait has ended is still mapped, once, and dropped.
    ///   Only the first completion of a run is ever mapped.
    /// - Cancellation stops no producer, request, retry or fallback. A producer that returns
    ///   without completing leaves the wait open until it completes or the task is cancelled; one
    ///   that never returns blocks inside the synchronous guarded call, which cancellation cannot
    ///   interrupt.
    /// - The run keeps the action until it delivers, so cancelling releases the waiting caller and
    ///   not the action.
    ///
    /// - Parameters:
    ///   - isolation: The isolation of the caller. Leave the default.
    ///   - mapSuccess: Maps the unwrapped payload of the success to a value that can cross
    ///     isolation domains.
    /// - Returns: The mapped value and the attempt label of the success.
    /// - Throws: The error of a failed run as it is, the error of `mapSuccess`, or
    ///   `CancellationError` when the cancellation ends the wait.
    func runAsync<Output: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        mapSuccess: @escaping @Sendable (any Copyable) throws -> Output
    ) async throws -> DMActionOutcome<Output> {
        try Task.checkCancellation()
        // The continuation of the stream owns the terminal state: the first `yield` followed by
        // `finish()` closes it, a later one is dropped, and a cancelled task ends the iteration.
        let stream = AsyncThrowingStream<DMActionOutcome<Output>, any Error>(bufferingPolicy: .bufferingNewest(1)) { sink in
            let completion: @Sendable (ResultType) -> Void = { result in
                switch mappedOutcome(of: result, using: mapSuccess) {
                case .success(let outcome):
                    sink.yield(outcome)
                    sink.finish()
                case .failure(let error):
                    sink.finish(throwing: error)
                }
            }
            self(completion: completion)
        }
        for try await outcome in stream {
            return outcome
        }
        throw CancellationError()
    }
}

private enum AsyncRunError: Error {
    /// A run labels every success it delivers, so this means the run broke its own rule. It ends
    /// the wait instead of inventing a label.
    case missingAttemptLabel
}

/// The outcome of a delivered result: the failure as it is, or the success mapped with its label.
private func mappedOutcome<Output: Sendable>(
    of result: DMAction.ResultType,
    using mapSuccess: @Sendable (any Copyable) throws -> Output
) -> Result<DMActionOutcome<Output>, any Error> {
    switch result.unwrapValue() {
    case .failure(let error):
        return .failure(error)
    case .success(let payload):
        guard let attemptCount = result.attemptCount else {
            return .failure(AsyncRunError.missingAttemptLabel)
        }
        do {
            return .success(DMActionOutcome(value: try mapSuccess(payload), attemptCount: attemptCount))
        } catch {
            return .failure(error)
        }
    }
}
