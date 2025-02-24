//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//
// Check the DMActionExtensionDocumentaryTests.swift to see for implemented examples

import Foundation

/// Protocol representing an action that can be performed.
/// It uses `ResultType` for the result and `ActionType` for the action itself.
public protocol DMAction {
    /// Type representing the result of the action, which can either be a `Copyable` or an `Error`.
    typealias ResultType = Result<Copyable, Error>
    
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
    func fallbackTo(_ fallback: DMAction) -> DMActionWithFallback {
        DMActionWithFallback(currentAttempt: self.currentAttempt + 1, self.action, fallback.action)
    }
    
    /// Returns a new action that retries this action the specified number of times.
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
    func retry(_ retryCount: UInt) -> DMAction {
        var currentAction: DMAction = self
        
        (0..<retryCount).forEach { _ in
            currentAction = currentAction.fallbackTo(self)
        }
        
        return currentAction
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
        self.action { result in
            let finalResult = Self.mapResultWithAttempt(result, attempt: result.attemptCount ?? currentAttempt)
            completion(finalResult)
        }
    }
}
