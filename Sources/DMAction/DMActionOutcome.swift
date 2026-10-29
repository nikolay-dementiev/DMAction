//
//  DMAction
//
//  Created by Mykola Dementiev
//

/// What ``DMAction/runAsync(isolation:mapSuccess:)`` returns: the mapped value of a success and
/// the attempt label of that success.
///
/// The value is what the caller's mapping made of the payload, so it is a type that can cross
/// isolation domains. The label is the one a run puts on a success: the action's
/// ``DMAction/currentAttempt`` plus the number of attempts that failed before this one, saturating
/// at `UInt.max`.
public struct DMActionOutcome<Output: Sendable>: Sendable {
    /// What the mapping returned for the payload of the success.
    public let value: Output

    /// The attempt label of the success.
    public let attemptCount: UInt
}
