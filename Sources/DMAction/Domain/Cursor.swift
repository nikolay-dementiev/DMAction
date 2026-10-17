//
//  DMAction
//
//  Created by Mykola Dementiev
//

// MARK: - Cursor

/// Where a run is: the frames from the outermost list of steps down to one producer, and how
/// many attempts of the run failed before this one.
struct Cursor {
    private let frames: [Frame]
    let produce: Producer
    /// The attempts of the run that failed before this one. It saturates at `.max`. Even at a
    /// billion attempts a second, a 64-bit `UInt` would take more than 500 years to get there;
    /// watchOS on arm64_32 has a 32-bit `UInt`, which a long enough run can reach.
    let failed: UInt

    /// The first producer of `plan`.
    init(first plan: ActionPlan) {
        var frames: [Frame] = []
        let produce = Self.enter(plan.steps, frames: &frames)
        self.init(frames: frames, produce: produce, failed: 0)
    }

    private init(frames: [Frame], produce: @escaping Producer, failed: UInt) {
        self.frames = frames
        self.produce = produce
        self.failed = failed
    }

    /// The producer that runs after this one fails, or nil when nothing is left to try.
    func next() -> Cursor? {
        var frames = self.frames
        while let frame = frames.popLast() {
            switch frame {
            case let .list(steps, index):
                guard index + 1 < steps.count else {
                    continue
                }
                frames.append(.list(steps, index: index + 1))
                let produce = Self.descend(into: steps[index + 1], frames: &frames)
                return Cursor(frames: frames, produce: produce, failed: failed.saturatingAdd(1))
            case let .repeating(unit, remaining):
                guard remaining > 0 else {
                    continue
                }
                frames.append(.repeating(unit, remaining: remaining - 1))
                let produce = Self.enter(unit.steps, frames: &frames)
                return Cursor(frames: frames, produce: produce, failed: failed.saturatingAdd(1))
            }
        }
        return nil
    }

    /// Opens a list of steps and goes down to its first producer.
    private static func enter(_ steps: [ActionPlan.Step], frames: inout [Frame]) -> Producer {
        frames.append(.list(steps, index: 0))
        return descend(into: steps[0], frames: &frames)
    }

    /// Goes down from `step` to its first producer, opening the repeated units on the way. A
    /// loop, not a recursion: units nested by repeated `retry` calls do not grow the stack.
    private static func descend(into step: ActionPlan.Step, frames: inout [Frame]) -> Producer {
        var step = step
        while true {
            switch step {
            case let .produce(produce):
                return produce
            case let .repeating(unit, retries):
                frames.append(.repeating(unit, remaining: retries))
                frames.append(.list(unit.steps, index: 0))
                step = unit.steps[0]
            }
        }
    }
}

private enum Frame {
    /// A list of steps, and the index of the step that runs.
    case list([ActionPlan.Step], index: Int)
    /// A repeated unit, and how many more runs of it remain.
    case repeating(ActionPlan, remaining: UInt)
}
