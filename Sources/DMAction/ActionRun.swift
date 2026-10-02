//
//  DMAction
//
//  Created by Mykola Dementiev
//

import Foundation
#if canImport(os)
import os
#endif

/// One run of a plan. Its attempts run in a loop on the thread that continues the run, so
/// the stack does not grow with the number of attempts or the length of a chain. The first
/// completion of an attempt moves the run on and any later one is ignored, so the consumer is
/// called at most once.
final class ActionRun {
    /// What the loop does next: start an attempt, or act on the result of one.
    private enum Work {
        case start(Cursor)
        case finish(Cursor, DMButtonAction.ResultType)
    }

    /// Each producer call gets its own, so that a late completion of an earlier call can be told
    /// apart from the completion of the current one.
    private final class Attempt {
        /// Where the attempt is in the plan. Its first completion takes it: a completion that
        /// finds it gone is a second one.
        var cursor: Cursor?
        /// The thread inside the producer call, until the call returns.
        var callingThread: Thread?
        /// The first result, when it arrived on the calling thread before the call returned.
        var deposit: DMButtonAction.ResultType?

        init(cursor: Cursor, callingThread: Thread) {
            self.cursor = cursor
            self.callingThread = callingThread
        }
    }

    /// The label of a success when no attempt failed before it.
    private let base: UInt
    /// The consumer's completion, until the run delivers to it. After that, a producer that
    /// keeps its own completion keeps nothing of the consumer alive.
    private var completion: ActionPlan.Completion?
    /// Guards `completion` and the state of every attempt of this run. No producer and no
    /// completion is ever called while it is held.
    private let lock = NSLock()

    init(base: UInt, completion: @escaping ActionPlan.Completion) {
        self.base = base
        self.completion = completion
    }

    func start(_ plan: ActionPlan) {
        drive(.start(Cursor(first: plan)))
    }

    /// Runs the attempts on this thread, one after another, until the run delivers, until an
    /// attempt waits for a completion that has not arrived yet, or until a completion on another
    /// thread has taken over the attempt this thread started.
    private func drive(_ first: Work) {
        var next: Work? = first
        while let work = next {
            next = nil
            switch work {
            case let .start(cursor):
                next = call(cursor).map { .finish(cursor, $0) }
            case let .finish(cursor, result):
                if case .failure = result, let following = cursor.next() {
                    next = .start(following)
                } else {
                    deliver(result)
                }
            }
        }
    }

    /// Calls the producer at `cursor` and returns its first result when that arrived on this
    /// thread before the call returned.
    private func call(_ cursor: Cursor) -> DMButtonAction.ResultType? {
        let attempt = Attempt(cursor: cursor, callingThread: Thread.current)
        // The run is held strongly: a producer may keep its completion and call it after
        // everything else has let go of the run.
        cursor.produce { result in
            self.complete(attempt, with: result)
        }
        lock.lock()
        attempt.callingThread = nil
        let deposit = attempt.deposit
        attempt.deposit = nil
        lock.unlock()
        return deposit
    }

    private func complete(_ attempt: Attempt, with result: DMButtonAction.ResultType) {
        lock.lock()
        guard let cursor = attempt.cursor else {
            lock.unlock()
            Self.reportIgnoredCompletion()
            return
        }
        attempt.cursor = nil
        // A label a producer put on its success is replaced: the run counts its own attempts.
        let labelled = DMButtonAction.mapResultWithAttempt(result, attempt: base.saturatingAdd(cursor.failed))
        // A completion on the thread that is still inside the producer call is kept for that
        // thread, which goes on when the call returns. A completion on any other thread goes
        // on at once: the producer may be waiting, inside its call, for an effect of this very
        // completion, and making the completion wait for the call would deadlock both.
        if attempt.callingThread === Thread.current {
            attempt.deposit = labelled
            lock.unlock()
            return
        }
        lock.unlock()
        drive(.finish(cursor, labelled))
    }

    private func deliver(_ result: DMButtonAction.ResultType) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(result)
    }

    /// There is no failure to hand to anyone: the extra completion has nowhere to go. One line
    /// in the unified log, at fault level, is the whole diagnostic.
    private static func reportIgnoredCompletion() {
        #if canImport(os)
        os_log(
            "A producer completed more than once. DMAction ignored the extra completion.",
            log: OSLog(subsystem: "DMAction", category: "ActionRun"),
            type: .fault
        )
        #endif
    }
}

// MARK: - Cursor

/// Where a run is: the frames from the outermost list of steps down to one producer, and how
/// many attempts of the run failed before this one.
struct Cursor {
    private let frames: [Frame]
    let produce: DMButtonAction.ActionType
    /// The attempts of the run that failed before this one.
    let failed: UInt

    /// The first producer of `plan`.
    init(first plan: ActionPlan) {
        var frames: [Frame] = []
        let produce = Self.enter(plan.steps, frames: &frames)
        self.init(frames: frames, produce: produce, failed: 0)
    }

    private init(frames: [Frame], produce: @escaping DMButtonAction.ActionType, failed: UInt) {
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
    private static func enter(_ steps: [ActionPlan.Step], frames: inout [Frame]) -> DMButtonAction.ActionType {
        frames.append(.list(steps, index: 0))
        return descend(into: steps[0], frames: &frames)
    }

    /// Goes down from `step` to its first producer, opening the repeated units on the way. A
    /// loop, not a recursion: units nested by repeated `retry` calls do not grow the stack.
    private static func descend(into step: ActionPlan.Step, frames: inout [Frame]) -> DMButtonAction.ActionType {
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
