//
//  DMAction
//
//  Created by Mykola Dementiev
//

/// A value that can carry the attempt label of a success.
///
/// ``DMActionResultValue`` is the conformer a run delivers. `Result.attemptCount` reads the
/// label of that type only.
public protocol DMActionResultValueProtocol: Copyable {
    /// The attempt label, or `nil` when the value carries none.
    var attemptCount: UInt? { get }
}

public extension DMActionResultValueProtocol {
    /// No label: a conformer that carries one implements this property.
    var attemptCount: UInt? { nil }
}

public extension Result where Success: Copyable, Failure == any Error {
    /// The result with its payload taken out of every ``DMActionResultValue`` layer. A failure
    /// stays as it is, the same error instance.
    ///
    /// ```swift
    /// import DMAction
    ///
    /// let greet = DMButtonAction { completion in completion(.success("Hello")) }
    /// greet { result in
    ///     if case .success(let value) = result.unwrapValue() {
    ///         print(value) // Hello, the payload the producer delivered
    ///     }
    /// }
    /// ```
    ///
    /// - Returns: The same result, with an unwrapped payload.
    func unwrapValue() -> DMAction.ResultType {
        map { DMActionResultValue.payload(of: $0) }
    }

    /// The attempt label of a success that a run delivered: the run's base plus the number of
    /// its attempts that failed before this success.
    ///
    /// `nil` for a failure, for a success whose value is not a ``DMActionResultValue`` (a value
    /// of another ``DMActionResultValueProtocol`` conformer included), and for a result after
    /// ``unwrapValue()``.
    var attemptCount: UInt? {
        guard case .success(let value) = self else {
            return nil
        }
        return (value as? DMActionResultValue)?.attemptCount
    }
}
