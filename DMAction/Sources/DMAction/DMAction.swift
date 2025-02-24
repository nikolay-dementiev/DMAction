import Foundation

public protocol DMAction {
    typealias ResultType = Result<Copyable, Error>
    typealias ActionType = (@escaping (ResultType) -> Void) -> Void
    
    var currentAttempt: UInt { get }
    var id: UUID { get }
    var action: ActionType { get }
    
    var simpleAction: () -> Void { get }
}

public extension DMAction {
    var simpleAction: () -> Void {
        {
            self.action { _ in }
        }
    }
    
    func fallbackTo(_ fallback: DMAction) -> DMActionWithFallback {
        DMActionWithFallback(currentAttempt: self.currentAttempt + 1, self.action, fallback.action)
    }
    
    func retry(_ retryCount: UInt) -> DMAction {
        var currentAction: DMAction = self
        
        (0..<retryCount).forEach { _ in
            currentAction = currentAction.fallbackTo(self)
        }
        
        return currentAction
    }
    
    func callAsFunction(completion: @escaping (ResultType) -> Void) {
        self.action { result in
            let finalResult = Self.mapResultWithAttempt(result, attempt: result.attemptCount ?? currentAttempt)
            completion(finalResult)
        }
    }
}

