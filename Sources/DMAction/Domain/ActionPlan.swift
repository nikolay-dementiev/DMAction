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
        case produce(Producer)
        /// The unit, then up to `retries` more runs of it while it fails.
        case repeating(ActionPlan, retries: UInt)
    }

    /// Run in order until one of them succeeds. Never empty: every plan starts from a first step.
    let steps: [Step]

    init(_ first: Step, _ rest: [Step] = []) {
        steps = [first] + rest
    }

    // Private, so that a plan is only ever built from a first step: `followed(by:)`, the one
    // caller, joins two plans that each have one. A run reads the first step unchecked.
    private init(steps: [Step]) {
        self.steps = steps
    }

    /// One flat list for `fallbackTo`, so that a long chain of fallbacks nests nothing.
    func followed(by next: ActionPlan) -> ActionPlan {
        ActionPlan(steps: steps + next.steps)
    }
}

extension ActionPlan {
    typealias Completion = (ProducerResult) -> Void
}

extension UInt {
    /// The sum, or `UInt.max` where the sum does not fit: an action that starts counting from
    /// a large value must not stop its host.
    func saturatingAdd(_ other: UInt) -> UInt {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}
