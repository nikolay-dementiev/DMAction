//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import Foundation

/// Protocol for result values of `DMAction` that can be copied and have an optional attempt count.
public protocol DMActionResultValueProtocol: Copyable {
    var attemptCount: UInt? { get }
}

/// Extension to provide a default implementation of `attemptCount` for `DMActionResultValueProtocol`.
public extension DMActionResultValueProtocol {
    var attemptCount: UInt? { nil }
}

/// Extension for `Result` where the success type conforms to `Copyable` and the failure type is `Error`.
public extension Result where Success: Copyable, Failure == Error {
    /// Unwrap the original result value that was passed via `ActionType`'s completion closure.
    ///
    /// - Returns: The original result value without any wrapper.
    ///
    /// Example:
    ///
    /// ```swift
    /// let result: Result<Copyable, Error> = // Your Result instance
    /// let unwrappedResult = result.unwrapValue()
    /// ```
    func unwrapValue() -> DMAction.ResultType {
        self.map(unwrapNestedResult)
    }
    
    /// The attempt count of the result.
    internal var attemptCount: UInt? {
        (try? self.get() as? DMActionResultValue)?.attemptCount
    }
    
    /// Unwrap nested `DMActionResultValue` to get the original result value.
    ///
    /// - Parameter value: The value to unwrap.
    /// - Returns: The original result value without any wrapper.
    private func unwrapNestedResult(_ value: Copyable) -> Copyable {
        var unwrappedValue: Copyable = value
        
        // Recursively unwrap nested DMActionResultValue
        while let nestedValue = (unwrappedValue as? DMActionResultValue)?.value {
            unwrappedValue = nestedValue
        }
        
        return unwrappedValue
    }
}

/// Internal extension for `DMAction` to map result with attempt count and unwrap nested results.
/// Used in the SDK itself.
internal extension DMAction {
    /// Map result with the attempt count.
    ///
    /// - Parameters:
    ///   - result: The result to map.
    ///   - attempt: The attempt count.
    /// - Returns: The mapped result with the attempt count.
    ///
    /// Example:
    ///
    /// ```swift
    /// let result: DMAction.ResultType = // Your Result instance
    /// let mappedResult = type(of: result).mapResultWithAttempt(result, attempt: 1)
    /// ```
    static func mapResultWithAttempt(_ result: ResultType, attempt: UInt) -> ResultType {
        result.map {
            let valueWithoutWrapper = unwrapNestedResult($0)
            return DMActionResultValue(value: valueWithoutWrapper, attemptCount: attempt) as DMActionResultValueProtocol
        }
    }
    
    /// Unwrap nested `DMActionResultValue` to get the original result value.
    ///
    /// - Parameter value: The value to unwrap.
    /// - Returns: The original result value without any wrapper.
    ///
    /// Example:
    ///
    /// ```swift
    /// let value: Copyable = // Your Copyable instance
    /// let unwrappedValue = type(of: value).unwrapNestedResult(value)
    /// ```
    static func unwrapNestedResult(_ value: Copyable) -> Copyable {
        var unwrappedValue: Copyable = value
        
        // Recursively unwrap nested DMActionResultValue
        while let nestedValue = (unwrappedValue as? DMActionResultValue)?.value {
            unwrappedValue = nestedValue
        }
        
        return unwrappedValue
    }
}
