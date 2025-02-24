//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import Foundation

public struct DMButtonAction: DMAction {
    private enum Settings {
        static let defaultAttemptCount: UInt = 0
    }
    
    public let currentAttempt: UInt
    public let id: UUID = UUID()
    
    public let action: ActionType
    
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
    
    public init(_ action: @escaping ActionType) {
        self.init(currentAttempt: Settings.defaultAttemptCount,
                  action: action)
    }
    
    public init(_ simpleAction: @escaping () -> Void) {
        self.init({ completion in
            simpleAction()
            completion(.success(DMActionResultValue(value: PlaceholderCopyable(),
                                                    attemptCount: Settings.defaultAttemptCount)))
        })
    }
}
