//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import Foundation

public protocol DMActionResultValueProtocol: Copyable {
    var attemptCount: UInt? { get }
}

public extension DMActionResultValueProtocol {
    var attemptCount: UInt? { nil }
}

public extension Result where Success: Copyable, Failure == Error {
    func unwrapValue() -> DMAction.ResultType {
        self.map(unwrapNestedResult)
    }
    
    internal var attemptCount: UInt? {
        (try? self.get() as? DMActionResultValue)?.attemptCount
    }
    
    private func unwrapNestedResult(_ value: Copyable) -> Copyable {
        var unwrappedValue: Copyable = value
        
        // Recursively unwrap nested DMActionResultValue
        while let nestedValue = (unwrappedValue as? DMActionResultValue)?.value {
            unwrappedValue = nestedValue
        }
        
        return unwrappedValue
    }
}

internal extension DMAction {
    static func mapResultWithAttempt(_ result: ResultType, attempt: UInt) -> ResultType {
        result.map {
            let valueWithoutWrapper = unwrapNestedResult($0)
            return DMActionResultValue(value: valueWithoutWrapper, attemptCount: attempt) as DMActionResultValueProtocol
        }
    }
    
    static func unwrapNestedResult(_ value: Copyable) -> Copyable {
        var unwrappedValue: Copyable = value
        
        // Recursively unwrap nested DMActionResultValue
        while let nestedValue = (unwrappedValue as? DMActionResultValue)?.value {
            unwrappedValue = nestedValue
        }
        
        return unwrappedValue
    }
}
