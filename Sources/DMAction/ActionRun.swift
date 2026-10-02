//
//  DMAction
//
//  Created by Mykola Dementiev
//

import Foundation

/// One run of a plan. Its attempts run in a loop on the thread that continues the run, so
/// the stack does not grow with the number of attempts or the length of a chain.
final class ActionRun {
    /// What the loop does next: start an attempt, or act on the result of one.
    private enum Work {
        case start(Cursor)
        case finish(Cursor, DMButtonAction.ResultType)
    }

    /// One call of a producer, and what its completion brought while the call was running.
    private final class Attempt {
        let cursor: Cursor
        /// The thread inside the producer call, until the call returns.
        var callingThread: Thread?
        /// The results that arrived on the calling thread before the call returned, in order.
        var deposits: [DMButtonAction.ResultType] = []

        init(cursor: Cursor, callingThread: Thread) {
            self.cursor = cursor
            self.callingThread = callingThread
        }
    }

    private let completion: ActionPlan.Completion
    /// Guards the `callingThread` and `deposits` of every attempt of this run. No producer
    /// and no completion is ever called while it is held.
    private let lock = NSLock()

    init(completion: @escaping ActionPlan.Completion) {
        self.completion = completion
    }

    func start(_ plan: ActionPlan) {
        drive([.start(Cursor(first: plan))])
    }

    /// Runs work on this thread until none is left: until the run delivers, or until an
    /// attempt waits for a completion that has not arrived yet.
    private func drive(_ initial: [Work]) {
        var work = initial
        while let item = work.popLast() {
            switch item {
            case let .start(cursor):
                // A producer that completed more than once continues the run once per result,
                // the first result first.
                work.append(contentsOf: call(cursor).reversed().map { .finish(cursor, $0) })
            case let .finish(cursor, result):
                if case .failure = result, let next = cursor.next() {
                    work.append(.start(next))
                } else {
                    completion(result)
                }
            }
        }
    }

    /// Calls the producer at `cursor` and returns what it delivered on this thread before the
    /// call returned.
    private func call(_ cursor: Cursor) -> [DMButtonAction.ResultType] {
        let attempt = Attempt(cursor: cursor, callingThread: Thread.current)
        cursor.produce { result in
            self.complete(attempt, with: cursor.relabel.label(result))
        }
        lock.lock()
        attempt.callingThread = nil
        let deposits = attempt.deposits
        attempt.deposits = []
        lock.unlock()
        return deposits
    }

    private func complete(_ attempt: Attempt, with result: DMButtonAction.ResultType) {
        lock.lock()
        // A completion on the thread that is still inside the producer call is kept for that
        // thread, which goes on when the call returns. A completion on any other thread goes
        // on at once: the producer may be waiting, inside its call, for an effect of this very
        // completion, and making the completion wait for the call would deadlock both.
        if attempt.callingThread === Thread.current {
            attempt.deposits.append(result)
            lock.unlock()
            return
        }
        lock.unlock()
        drive([.finish(attempt.cursor, result)])
    }
}

// MARK: - Cursor

/// Where a run is: the frames from the outermost list of steps down to one producer.
struct Cursor {
    private typealias Leaf = (produce: DMButtonAction.ActionType, relabel: Relabel)

    private let frames: [Frame]
    /// The producer this cursor points at.
    let produce: DMButtonAction.ActionType
    /// What becomes of the label of that producer's success.
    let relabel: Relabel

    /// The first producer of `plan`.
    init(first plan: ActionPlan) {
        var frames: [Frame] = []
        let leaf = Self.enter(plan.steps, relabel: .keep, frames: &frames)
        self.init(frames: frames, leaf: leaf)
    }

    private init(frames: [Frame], leaf: Leaf) {
        self.frames = frames
        self.produce = leaf.produce
        self.relabel = leaf.relabel
    }

    /// The producer that runs after this one fails, or nil when nothing is left to try.
    func next() -> Cursor? {
        var frames = self.frames
        while let frame = frames.popLast() {
            switch frame {
            case let .list(steps, index, relabel):
                guard index + 1 < steps.count else {
                    continue
                }
                frames.append(.list(steps, index: index + 1, relabel: relabel))
                let leaf = Self.descend(into: steps[index + 1], relabel: relabel, frames: &frames)
                return Cursor(frames: frames, leaf: leaf)
            case let .repeating(unit, run, remaining, base, relabel):
                guard remaining > 0 else {
                    continue
                }
                let nextRun = run.saturatingAdd(1)
                frames.append(.repeating(unit, run: nextRun, remaining: remaining - 1, base: base, relabel: relabel))
                let runRelabel = relabel.applied(over: .override(base.saturatingAdd(nextRun)))
                let leaf = Self.enter(unit.steps, relabel: runRelabel, frames: &frames)
                return Cursor(frames: frames, leaf: leaf)
            }
        }
        return nil
    }

    /// Opens a list of steps and goes down to its first producer.
    private static func enter(_ steps: [ActionPlan.Step], relabel: Relabel, frames: inout [Frame]) -> Leaf {
        frames.append(.list(steps, index: 0, relabel: relabel))
        return descend(into: steps[0], relabel: relabel, frames: &frames)
    }

    /// Goes down from `step` to its first producer, opening the repeated units on the way. A
    /// loop, not a recursion: units nested by repeated `retry` calls do not grow the stack.
    private static func descend(into step: ActionPlan.Step, relabel: Relabel, frames: inout [Frame]) -> Leaf {
        var step = step
        var outer = relabel
        while true {
            switch step {
            case let .produce(produce, own):
                return (produce, outer.applied(over: own))
            case let .repeating(unit, retries, base, own):
                let unitRelabel = outer.applied(over: own)
                frames.append(.repeating(unit, run: 1, remaining: retries, base: base, relabel: unitRelabel))
                outer = unitRelabel.applied(over: .keepOrDefault(base.saturatingAdd(1)))
                frames.append(.list(unit.steps, index: 0, relabel: outer))
                step = unit.steps[0]
            }
        }
    }
}

/// One level of a cursor.
private enum Frame {
    /// A list of steps, and the index of the step that runs.
    case list([ActionPlan.Step], index: Int, relabel: Relabel)
    /// A repeated unit: which run of it this is, and how many runs remain after it.
    case repeating(ActionPlan, run: UInt, remaining: UInt, base: UInt, relabel: Relabel)
}
