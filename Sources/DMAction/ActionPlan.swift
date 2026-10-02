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
        /// One call of a producer. The relabel says what becomes of the label of its success.
        case produce(DMButtonAction.ActionType, Relabel)
        /// The unit, then up to `retries` more runs of it while it fails. Run n of the unit
        /// is labelled the way the n-th action of a `fallbackTo` chain starting at `base` was.
        case repeating(ActionPlan, retries: UInt, base: UInt, Relabel)
    }

    /// Run in order until one of them succeeds. Never empty.
    let steps: [Step]
}

/// What becomes of the attempt label of a success.
enum Relabel {
    /// The success keeps the label it has, or none.
    case keep
    /// A success that has a label keeps it. One without a label gets this one.
    case keepOrDefault(UInt)
    /// The success gets this label.
    case override(UInt)

    /// The relabel that applies `inner` first and this one after it.
    func applied(over inner: Relabel) -> Relabel {
        switch self {
        case .keep:
            return inner
        case .override:
            return self
        case .keepOrDefault:
            if case .keep = inner {
                return self
            }
            return inner
        }
    }

    func label(_ result: DMButtonAction.ResultType) -> DMButtonAction.ResultType {
        switch self {
        case .keep:
            return result
        case .keepOrDefault(let attempt):
            return DMButtonAction.mapResultWithAttempt(result, attempt: result.attemptCount ?? attempt)
        case .override(let attempt):
            return DMButtonAction.mapResultWithAttempt(result, attempt: attempt)
        }
    }
}

extension ActionPlan {
    /// The plan of an action. A built-in action carries its own. Any other conformer is one
    /// call of its `action`, which is read here, once.
    init(of action: any DMAction) {
        switch action {
        case let button as DMButtonAction:
            self = button.plan
        case let composed as DMActionWithFallback:
            self = composed.plan
        default:
            self.init(steps: [.produce(action.action, .keep)])
        }
    }

    /// The same steps, each with `outer` applied after its own relabel.
    func relabeled(_ outer: Relabel) -> ActionPlan {
        ActionPlan(steps: steps.map { step in
            switch step {
            case let .produce(produce, relabel):
                return .produce(produce, outer.applied(over: relabel))
            case let .repeating(unit, retries, base, relabel):
                return .repeating(unit, retries: retries, base: base, outer.applied(over: relabel))
            }
        })
    }
}

// MARK: - Running

extension ActionPlan {
    typealias Completion = (DMButtonAction.ResultType) -> Void

    /// Runs the steps in order and calls `completion` with the first success, labelled, or
    /// with the failure of the last step. A step starts inside the completion call of the
    /// step before it, as it did when a composition was a chain of nested closures.
    func run(_ completion: @escaping Completion) {
        run(from: 0, relabel: .keep, completion: completion)
    }

    private func run(from index: Int, relabel outer: Relabel, completion: @escaping Completion) {
        let next: Completion = { result in
            if case .failure = result, index + 1 < steps.count {
                run(from: index + 1, relabel: outer, completion: completion)
            } else {
                completion(result)
            }
        }
        switch steps[index] {
        case let .produce(produce, relabel):
            let label = outer.applied(over: relabel)
            produce { result in
                next(label.label(result))
            }
        case let .repeating(unit, retries, base, relabel):
            unit.repeatedly(
                from: 1,
                remaining: retries,
                base: base,
                relabel: outer.applied(over: relabel),
                completion: next
            )
        }
    }

    /// Run `number` of a repeated unit, then the runs after it while they fail. The runs that
    /// remain are counted down, so nothing is ever computed past `retries`.
    private func repeatedly(
        from number: UInt,
        remaining: UInt,
        base: UInt,
        relabel: Relabel,
        completion: @escaping Completion
    ) {
        let runLabel: Relabel = number == 1
            ? .keepOrDefault(base.saturatingAdd(1))
            : .override(base.saturatingAdd(number))
        run(from: 0, relabel: relabel.applied(over: runLabel)) { result in
            if case .failure = result, remaining > 0 {
                repeatedly(
                    from: number.saturatingAdd(1),
                    remaining: remaining - 1,
                    base: base,
                    relabel: relabel,
                    completion: completion
                )
            } else {
                completion(result)
            }
        }
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
