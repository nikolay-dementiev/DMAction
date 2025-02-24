//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import Foundation

/// A struct representing an action with a fallback that conforms to the `DMAction` protocol.
public struct DMActionWithFallback: DMAction {
    /// The current attempt number of the action.
    public let currentAttempt: UInt
    
    /// The unique identifier of the action.
    public let id: UUID = UUID()
    
    /// The action to be performed.
    public let action: ActionType
    
    /// Initializes a new instance of `DMActionWithFallback` with the specified primary and fallback actions.
    ///
    /// - Parameters:
    ///   - currentAttempt: The current attempt number.
    ///   - primaryAction: The primary action to be performed.
    ///   - fallbackAction: The fallback action to be performed if the primary action fails.
    public init(currentAttempt: UInt,
                _ primaryAction: @escaping ActionType,
                _ fallbackAction: @escaping ActionType) {
        self.currentAttempt = currentAttempt
        self.action = { [fallbackAction] completion in
            primaryAction { result in
                switch result {
                case .success:
                    let finalResult = Self.mapResultWithAttempt(result,
                                                                attempt: result.attemptCount ?? currentAttempt)
                    completion(finalResult)
                case .failure:
                    let fallbackActionWithIncrement = DMButtonAction(currentAttempt: currentAttempt + 1,
                                                                     action: fallbackAction)
                    fallbackActionWithIncrement.action(completion)
                }
            }
        }
    }
}
