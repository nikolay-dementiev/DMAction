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

    /// What `action` runs.
    let plan: ActionPlan

    /// Initializes a new instance of `DMActionWithFallback` with the specified primary and fallback actions.
    ///
    /// - Parameters:
    ///   - currentAttempt: The current attempt number.
    ///   - primaryAction: The primary action to be performed.
    ///   - fallbackAction: The fallback action to be performed if the primary action fails.
    public init(currentAttempt: UInt,
                _ primaryAction: @escaping ActionType,
                _ fallbackAction: @escaping ActionType) {
        self.init(currentAttempt: currentAttempt, plan: ActionPlan(steps: [
            .produce(primaryAction, .keepOrDefault(currentAttempt)),
            .produce(fallbackAction, .override(currentAttempt.saturatingAdd(1)))
        ]))
    }

    init(currentAttempt: UInt, plan: ActionPlan) {
        self.currentAttempt = currentAttempt
        self.plan = plan
        self.action = { completion in
            plan.run(completion)
        }
    }
}
