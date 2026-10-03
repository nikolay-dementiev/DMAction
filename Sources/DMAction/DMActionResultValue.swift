//
//  DMAction
//
//  Created by Mykola Dementiev
//

/// The wrapper in which a run delivers a success: the payload and its attempt label.
///
/// A run takes the payload out of any wrappers a producer delivered and wraps it once, with
/// the run's own label. `unwrapValue()` and `attemptCount` on `Result` read the two.
public struct DMActionResultValue: DMActionResultValueProtocol {
    /// The attempt label: in a delivered result, the run's base plus the number of attempts
    /// that failed before this success. `nil` for a value created without one.
    public let attemptCount: UInt?

    /// The payload.
    public let value: any Copyable

    /// Creates a wrapper.
    ///
    /// A producer may deliver one, but a run replaces its label with the run's own count and
    /// takes its payload out of every layer.
    ///
    /// - Parameters:
    ///   - value: The payload.
    ///   - attemptCount: The attempt label, or `nil` for none.
    public init(value: any Copyable,
                attemptCount: UInt? = nil) {
        self.value = value
        self.attemptCount = attemptCount
    }
}

extension DMActionResultValue {
    /// The value inside any number of wrappers.
    static func payload(of value: any Copyable) -> any Copyable {
        var payload = value
        while let wrapper = payload as? DMActionResultValue {
            payload = wrapper.value
        }
        return payload
    }

    /// The success of `result` with its payload in one wrapper that carries `attempt`. A failure
    /// stays as it is.
    static func labelling(_ result: DMButtonAction.ResultType, attempt: UInt) -> DMButtonAction.ResultType {
        result.map { DMActionResultValue(value: payload(of: $0), attemptCount: attempt) }
    }
}

/// The payload of a success that has nothing to carry: what a ``DMButtonAction`` made from a
/// closure that cannot fail delivers.
public struct PlaceholderCopyable: Copyable {
    /// Creates the placeholder.
    public init() { }
}
