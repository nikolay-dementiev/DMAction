//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import Foundation

/// A struct representing the result value of a `DMAction` with an optional attempt count.
/// Used to wrap Original DMAction.ResultType inside this Object and provide `attemptCount`
/// for final Result closure
/// Conforms to `DMActionResultValueProtocol`.
public struct DMActionResultValue: DMActionResultValueProtocol {
    /// The attempt count of the action result.
    public let attemptCount: UInt?
    
    /// The value of the action result.
    public let value: Copyable
    
    /// Initializes a new instance of `DMActionResultValue`.
    ///
    /// - Parameters:
    ///   - value: The value of the action result.
    ///   - attemptCount: The optional attempt count of the action result.
    public init(value: Copyable,
                attemptCount: UInt? = nil) {
        self.value = value
        self.attemptCount = attemptCount
    }
}

/// A struct representing a placeholder value that conforms to `Copyable`.
public struct PlaceholderCopyable: Copyable {
    /// Initializes a new instance of `PlaceholderCopyable`.
    public init() { }
}
