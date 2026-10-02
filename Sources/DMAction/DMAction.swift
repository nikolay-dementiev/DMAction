//
//  DMAction
//
//  Created by Mykola Dementiev
//

import Foundation

/// Protocol representing an action that can be performed.
/// It uses `ResultType` for the result and `ActionType` for the action itself.
public protocol DMAction {
    /// Type representing the result of the action, which can either be a `Copyable` or an `Error`.
    typealias ResultType = Result<any Copyable, any Error>

    /// Type representing the action, which is a closure that takes a completion handler.
    typealias ActionType = (@escaping (ResultType) -> Void) -> Void

    /// The current attempt number of the action.
    var currentAttempt: UInt { get }

    /// The unique identifier of the action.
    var id: UUID { get }

    /// The action to be performed.
    var action: ActionType { get }

    /// A simplified version of the action.
    var simpleAction: () -> Void { get }
}

public extension DMAction {
    /// A simplified version of the action that ignores the result.
    ///
    /// Example:
    ///
    /// ```swift
    /// let action: DMAction = // Your DMAction instance
    /// action.simpleAction()
    /// ```
    var simpleAction: () -> Void {
        {
            self.action { _ in }
        }
    }

    /// Returns a new action that falls back to the given action if this action fails.
    ///
    /// A chain of fallbacks of any length runs without growing the stack, with the exception
    /// that `retry(_:)` describes: a producer that blocks its thread until a completion it
    /// handed to another thread has returned.
    ///
    /// - Parameter fallback: The action to fall back to.
    /// - Returns: A new action with fallback.
    ///
    /// Example:
    ///
    /// ```swift
    /// let action1: DMAction = // Your DMAction instance
    /// let action2: DMAction = // Another DMAction instance
    /// let actionWithFallback = action1.fallbackTo(action2)
    /// actionWithFallback.action { result in
    ///     // Handle result
    /// }
    /// ```
    func fallbackTo(_ fallback: any DMAction) -> DMActionWithFallback {
        let attempt = currentAttempt
        let plan = ActionPlan(of: self).followed(by: ActionPlan(of: fallback))
        return DMActionWithFallback(currentAttempt: attempt, plan: plan)
    }

    /// Returns a new action that retries this action the specified number of times.
    ///
    /// Running the new action does not grow the stack with the number of attempts, as long as
    /// each producer completes on its calling thread during its call, or after its call has
    /// returned. A producer that blocks its thread until a completion it handed to another
    /// thread has returned is nested once per attempt, so many such attempts can overflow
    /// the stack.
    ///
    /// - Parameter retryCount: The number of times to retry the action.
    /// - Returns: A new action with retries.
    ///
    /// Example:
    ///
    /// ```swift
    /// let action: DMAction = // Your DMAction instance
    /// let actionWithRetries = action.retry(3)
    /// actionWithRetries.action { result in
    ///     // Handle result
    /// }
    /// ```
    func retry(_ retryCount: UInt) -> any DMAction {
        guard retryCount > 0 else {
            return self
        }
        let attempt = currentAttempt
        let plan = ActionPlan(.repeating(ActionPlan(of: self), retries: retryCount))
        return DMActionWithFallback(currentAttempt: attempt, plan: plan)
    }

    /// Performs the action and calls the completion handler with the result.
    ///
    /// - Parameter completion: The completion handler to call with the result.
    ///
    /// Example:
    ///
    /// ```swift
    /// let action: DMAction = // Your DMAction instance
    /// action { result in
    ///     switch result {
    ///     case .success(let value):
    ///         print("Success with value: \(value)")
    ///     case .failure(let error):
    ///         print("Failed with error: \(error)")
    ///     }
    /// }
    /// ```
    func callAsFunction(completion: @escaping (ResultType) -> Void) {
        // The order is part of the contract, for a conformer whose getters have effects:
        // `action`, then `currentAttempt`, both at the call.
        let plan = ActionPlan(of: self)
        plan.run(base: currentAttempt, completion)
    }
}
