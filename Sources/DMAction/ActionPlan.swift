//
//  DMAction
//
//  Created by Mykola Dementiev
//

/// What a built-in action runs, as data. `retry` stores its count instead of building one
/// action per retry, and `fallbackTo` joins the steps of its two operands into one list.
struct ActionPlan {
    /// One call of a producer, or a unit of steps that runs again while it fails.
    enum Step {
        /// One call of a producer.
        case produce(DMButtonAction.ActionType)
        /// The unit, then up to `retries` more runs of it while it fails.
        case repeating(ActionPlan, retries: UInt)
    }

    /// Run in order until one of them succeeds. Never empty.
    let steps: [Step]
}

extension ActionPlan {
    typealias Completion = (DMButtonAction.ResultType) -> Void

    /// The plan of an action. A built-in action carries its own. Any other conformer is one
    /// call of its `action`, which is read here, once.
    init(of action: any DMAction) {
        switch action {
        case let button as DMButtonAction:
            self = button.plan
        case let composed as DMActionWithFallback:
            self = composed.plan
        default:
            self.init(steps: [.produce(action.action)])
        }
    }

    /// Runs the steps in order and calls `completion` with the first success or with the
    /// failure of the last step. A success is labelled `base` plus the number of attempts that
    /// failed before it in this run. Each run is an `ActionRun` of its own.
    func run(base: UInt, _ completion: @escaping Completion) {
        ActionRun(base: base, completion: completion).start(self)
    }
}

extension UInt {
    /// The sum, or `UInt.max` where the sum does not fit: an action that starts counting from
    /// a large value must not stop its host.
    func saturatingAdd(_ other: UInt) -> UInt {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}
