//
//  DMAction
//
//  Created by Mykola Dementiev
//

import Foundation

/// Work that reports one result through a completion, and that composes with fallbacks and
/// retries.
///
/// The library's conformers are ``DMButtonAction`` and ``DMActionWithFallback``. Run an action
/// with ``callAsFunction(completion:)`` or through its ``action``. ``fallbackTo(_:)`` and
/// ``retry(_:)`` build new actions and run nothing.
///
/// A run calls the first producer on the calling thread before the call returns, and delivers
/// at most one result. <doc:RunningActions> says what a producer must do, what the library
/// enforces and what it cannot promise. Nothing here is `Sendable`: use an action inside one
/// isolation domain.
public protocol DMAction {
    /// The result of a run: a success with any `Copyable` payload, or an error.
    ///
    /// A run of the library delivers a success as a ``DMActionResultValue`` that holds the
    /// payload and its attempt label. `unwrapValue()` and `attemptCount` on `Result` read them.
    typealias ResultType = Result<any Copyable, any Error>

    /// A producer: it receives a completion and calls it once with the result of its work,
    /// before it returns or later, on any thread.
    typealias ActionType = (@escaping (ResultType) -> Void) -> Void

    /// The label of a success on the first attempt of a run of this action.
    ///
    /// A run labels a success with this value plus the number of its attempts that failed
    /// before it, saturating at `UInt.max`. ``fallbackTo(_:)`` and ``retry(_:)`` keep the
    /// receiver's value.
    var currentAttempt: UInt { get }

    /// An identifier of this value. A copy shares it; every composition gets a new one.
    var id: UUID { get }

    /// Runs the action and calls the given completion with its result.
    ///
    /// For the library's conformers this is a guarded run (<doc:RunningActions>). The `action`
    /// of a third-party conformer is its own closure: called directly, nothing guards it.
    var action: ActionType { get }

    /// Runs the action and drops its result, a failure included.
    var simpleAction: () -> Void { get }
}

public extension DMAction {
    /// Runs the action and drops its result, a failure included.
    ///
    /// A conformer that supplies its own `simpleAction` keeps it. This default calls ``action``,
    /// so for a third-party conformer it is that conformer's closure, not a guarded run.
    ///
    /// ```swift
    /// let tap: any DMAction = DMButtonAction { print("Tapped") }
    /// tap.simpleAction()
    /// ```
    var simpleAction: () -> Void {
        {
            self.action { _ in }
        }
    }

    /// Returns an action that runs this action and, when it fails, the given one.
    ///
    /// The new action delivers the first success, or the error of `fallback`. Building it runs
    /// nothing; it reads the `currentAttempt` and `action` of a third-party receiver, and the
    /// `action` of a third-party `fallback`, once each. Its ``currentAttempt`` is this action's,
    /// and a success of `fallback` is labelled one higher for every attempt that failed before it.
    ///
    /// A chain of fallbacks of any length runs without growing the stack, with the exception
    /// that ``retry(_:)`` describes: a producer that blocks its thread until a completion it
    /// handed to another thread has returned.
    ///
    /// ```swift
    /// let fresh: any DMAction = DMButtonAction { completion in completion(.failure(URLError(.timedOut))) }
    /// let cached: any DMAction = DMButtonAction { completion in completion(.success("cached")) }
    ///
    /// let freshOrCached = fresh.fallbackTo(cached)
    /// freshOrCached { result in
    ///     print(result.attemptCount ?? 0) // 1: one attempt failed before the success
    /// }
    /// ```
    ///
    /// - Parameter fallback: The action to run when this one fails.
    /// - Returns: The composed action.
    func fallbackTo(_ fallback: any DMAction) -> DMActionWithFallback {
        let attempt = currentAttempt
        let plan = ActionPlan(of: self).followed(by: ActionPlan(of: fallback))
        return DMActionWithFallback(currentAttempt: attempt, plan: plan)
    }

    /// Returns an action that runs this action again, up to `retryCount` more times, while it
    /// fails.
    ///
    /// A retry starts right after the failure, whatever the error, a `CancellationError`
    /// included. The new action delivers the first success, or the error of the last attempt.
    /// `retry(0)` returns this action itself. Any count, `UInt.max` included, costs the same to
    /// build; building runs nothing and, for a third-party conformer, reads its `currentAttempt`
    /// and `action` once each. Retrying a composite repeats the whole composite.
    ///
    /// Running the new action does not grow the stack with the number of attempts, as long as
    /// each producer completes on its calling thread during its call, or after its call has
    /// returned. A producer that blocks its thread until a completion it handed to another
    /// thread has returned is nested once per attempt, so many such attempts can overflow
    /// the stack.
    ///
    /// ```swift
    /// var calls = 0
    /// let flaky = DMButtonAction { completion in
    ///     calls += 1
    ///     completion(calls < 3 ? .failure(URLError(.timedOut)) : .success("done"))
    /// }
    ///
    /// flaky.retry(3).action { result in
    ///     print(result.attemptCount ?? 0) // 2: two attempts failed before the success
    /// }
    /// ```
    ///
    /// Swift 6.3 crashes when call syntax is applied directly to the value this returns, as in
    /// `flaky.retry(3)(completion: handle)`. Store it in a constant first, or call ``action``.
    ///
    /// - Parameter retryCount: How many times to run this action again after a failure.
    /// - Returns: The composed action, or this action for a count of zero.
    func retry(_ retryCount: UInt) -> any DMAction {
        guard retryCount > 0 else {
            return self
        }
        let attempt = currentAttempt
        let plan = ActionPlan(.repeating(ActionPlan(of: self), retries: retryCount))
        return DMActionWithFallback(currentAttempt: attempt, plan: plan)
    }

    /// Runs the action as a guarded run, whatever the conformer, and calls `completion` at most
    /// once with the result.
    ///
    /// The first producer runs on the calling thread before this returns. When every producer
    /// completes on the calling thread before it returns, `completion` runs on that thread before
    /// this call returns too; otherwise it runs on the thread of the last completion. A
    /// third-party conformer's `action` and then its `currentAttempt` are read when this is called.
    ///
    /// ```swift
    /// let greet = DMButtonAction { completion in completion(.success("Hello")) }
    ///
    /// greet { result in
    ///     switch result.unwrapValue() {
    ///     case .success(let value):
    ///         print(value) // Hello
    ///     case .failure(let error):
    ///         print(error)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter completion: Receives the first success, or the error of the last attempt.
    func callAsFunction(completion: @escaping (ResultType) -> Void) {
        // The order is part of the contract, for a conformer whose getters have effects:
        // `action`, then `currentAttempt`, both at the call.
        let plan = ActionPlan(of: self)
        // The run keeps the receiver until it delivers, as call syntax did in 1.0.5: a
        // conformer's producer may refer to the conformer without retaining it.
        plan.run(base: currentAttempt) { result in
            withExtendedLifetime(self) {
                completion(result)
            }
        }
    }
}
