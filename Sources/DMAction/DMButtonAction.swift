//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//
// Check the DMButtonActionObjectsDocumentaryTests.swift to see for implemented examples

import Foundation

/// A struct representing a button action that conforms to the `DMAction` protocol.
///
/// Example of how to use `DMButtonAction` with a simple action:
///
/// ```swift
/// let buttonAction = DMButtonAction {
///     print("Button action performed")
/// }
///
/// buttonAction.action { result in
///     switch result {
///     case .success(let value):
///         print("Success with value: \(value)")
///     case .failure(let error):
///         print("Failed with error: \(error)")
///     }
/// }
/// ```
///
/// Example of how to use `DMButtonAction` with an action closure:
///
/// ```swift
/// let buttonActionWithClosure = DMButtonAction { completion in
///     // Perform some async task
///     completion(.success(DMActionResultValue(value: PlaceholderCopyable(),
///                                             attemptCount: 0)))
/// }
///
/// buttonActionWithClosure.action { result in
///     switch result {
///     case .success(let value):
///         print("Success with value: \(value)")
///     case .failure(let error):
///         print("Failed with error: \(error)")
///     }
/// }
/// ```
public struct DMButtonAction: DMAction {
    /// Settings used for the default attempt count.
    private enum Settings {
        static let defaultAttemptCount: UInt = 0
    }
    
    /// The current attempt number of the action.
    public let currentAttempt: UInt
    
    /// The unique identifier of the action.
    public let id: UUID = UUID()
    
    /// The action to be performed.
    public let action: ActionType
    
    /// Initializes a new instance of `DMButtonAction` with the specified current attempt and action.
    ///
    /// - Parameters:
    ///   - currentAttempt: The current attempt number.
    ///   - action: The action to be performed.
    internal init(currentAttempt: UInt,
                  action: @escaping ActionType) {
        self.currentAttempt = currentAttempt
        self.action = { completion in
            action { result in
                let finalResult = Self.mapResultWithAttempt(result, attempt: currentAttempt)
                completion(finalResult)
            }
        }
    }
    
    /// Initializes a new instance of `DMButtonAction` with the default attempt count and the specified action.
    ///
    /// - Parameter action: The action to be performed.
    public init(_ action: @escaping ActionType) {
        self.init(currentAttempt: Settings.defaultAttemptCount,
                  action: action)
    }
    
    /// Initializes a new instance of `DMButtonAction` with the default attempt count and a simple action.
    ///
    /// - Parameter simpleAction: The simple action to be performed.
    public init(_ simpleAction: @escaping () -> Void) {
        self.init({ completion in
            simpleAction()
            completion(.success(DMActionResultValue(value: PlaceholderCopyable(),
                                                    attemptCount: Settings.defaultAttemptCount)))
        })
    }
}
