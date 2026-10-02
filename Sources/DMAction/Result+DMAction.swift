//
//  DMAction
//
//  Created by Mykola Dementiev
//

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
        map { DMActionResultValue.payload(of: $0) }
    }

    /// The attempt count of the result.
    var attemptCount: UInt? {
        guard case .success(let value) = self else {
            return nil
        }
        return (value as? DMActionResultValue)?.attemptCount
    }
}
