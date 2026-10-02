//
//  DMAction
//
//  Created by Mykola Dementiev
//

import Foundation

/// A composed action: producers that run in order until one succeeds.
///
/// ``DMAction/fallbackTo(_:)`` and ``DMAction/retry(_:)`` return their compositions as this
/// type, and ``init(currentAttempt:_:_:)`` builds one from two producers. Every run of it is
/// guarded, as <doc:RunningActions> describes.
public struct DMActionWithFallback: DMAction {
    /// The label of a success on the first attempt of a run of this action. A success after
    /// failed attempts is labelled this value plus their number, saturating at `UInt.max`.
    public let currentAttempt: UInt

    /// An identifier of this value. A copy shares it; every composition gets a new one.
    public let id: UUID = UUID()

    /// Runs the producers in order until one succeeds, as one guarded run, and calls the given
    /// completion at most once with the first success or the error of the last attempt.
    public let action: ActionType

    /// What `action` runs.
    let plan: ActionPlan

    /// Creates an action that runs `primaryAction` and, when it fails, `fallbackAction`.
    ///
    /// A success of the primary is labelled `currentAttempt`, a success of the fallback
    /// `currentAttempt + 1`, saturating at `UInt.max`. A producer is opaque to the run: a
    /// composed action passed here as `action` counts as one attempt, whatever happened inside
    /// it. Build a chain with ``DMAction/fallbackTo(_:)`` for an exact count.
    ///
    /// - Parameters:
    ///   - currentAttempt: The label of a success of the primary.
    ///   - primaryAction: The producer that runs first.
    ///   - fallbackAction: The producer that runs when the primary fails.
    public init(currentAttempt: UInt,
                _ primaryAction: @escaping ActionType,
                _ fallbackAction: @escaping ActionType) {
        self.init(currentAttempt: currentAttempt, plan: ActionPlan(.produce(primaryAction), [.produce(fallbackAction)]))
    }

    init(currentAttempt: UInt, plan: ActionPlan) {
        self.currentAttempt = currentAttempt
        self.plan = plan
        self.action = { completion in
            plan.run(base: currentAttempt, completion)
        }
    }
}
