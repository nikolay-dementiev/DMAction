//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import Foundation

public struct DMActionWithFallback: DMAction {
    public let currentAttempt: UInt
    public let id: UUID = UUID()
    public let action: ActionType
    
    // Initialize with primary and fallback actions
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
