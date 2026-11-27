//
//  DMAction
//
//  Created by Mykola Dementiev
//

import Foundation
internal import DMCore
#if canImport(os)
import os
#endif

/// One run of a plan. Its attempts run in a loop on the thread that continues the run, so
/// the stack does not grow with the number of attempts or the length of a chain, as long as
/// no producer blocks its thread until a completion it handed to another thread has returned.
/// Such a completion can arrive on a thread that is still inside an older producer call of the
/// run. It continues the run there, one level deeper per attempt, because making it wait for
/// that call could deadlock both. The first completion of an attempt moves the run on and any
/// later one is ignored, so the consumer is called at most once.
final class ActionRun {
    /// What the loop does next: start an attempt, or act on the result of one.
    private enum Work {
        case start(Cursor)
        case finish(Cursor, ProducerResult)
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
        var deposit: ProducerResult?
        /// The signpost interval of the attempt. The completion that takes the cursor ends it.
        let interval: TraceInterval

        init(cursor: Cursor, callingThread: Thread, interval: TraceInterval) {
            self.cursor = cursor
            self.callingThread = callingThread
            self.interval = interval
        }
    }

    /// The label of a success when no attempt failed before it.
    private let base: UInt
    /// Where the run reports what it does, for a performance tool.
    private let tracing: any Tracing
    /// The signpost interval of the run, from its start to its delivery.
    private let interval: TraceInterval
    /// The consumer's completion, until the run delivers to it. After that, a producer that
    /// keeps its own completion keeps nothing of the consumer alive.
    private var completion: ActionPlan.Completion?
    /// Guards `completion` and the state of every attempt of this run. No producer, no
    /// completion and no tracing call is ever made while it is held.
    private let lock = NSLock()

    init(base: UInt, tracing: any Tracing, completion: @escaping ActionPlan.Completion) {
        self.base = base
        self.tracing = tracing
        self.completion = completion
        interval = tracing.beginInterval("run", Self.detail(base))
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
                    let move: StaticString = switch following.move {
                    case .fallback: "fallback"
                    case .retry: "retry"
                    }
                    tracing.emitEvent(move, Self.detail(label(of: following.cursor)))
                    next = .start(following.cursor)
                } else {
                    // A label a producer put on its success is replaced: the run counts its own
                    // attempts.
                    deliver(DMActionResultValue.labelling(result, attempt: label(of: cursor)))
                }
            }
        }
    }

    /// Calls the producer at `cursor` and returns its first result when that arrived on this
    /// thread before the call returned.
    ///
    /// The caller keeps `cursor`, and with it the frames and the plan, until this returns. So
    /// they are released after the delivery once every producer call of the run has returned,
    /// not while a producer is still inside its call.
    private func call(_ cursor: Cursor) -> ProducerResult? {
        let attempt = Attempt(
            cursor: cursor,
            callingThread: Thread.current,
            interval: tracing.beginInterval("attempt", Self.detail(label(of: cursor)))
        )
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

    private func complete(_ attempt: Attempt, with result: ProducerResult) {
        lock.lock()
        guard let cursor = attempt.cursor else {
            lock.unlock()
            tracing.emitEvent("ignoredCompletion")
            Self.reportIgnoredCompletion()
            return
        }
        attempt.cursor = nil
        // A completion on the thread that is still inside the producer call is kept for that
        // thread, which goes on when the call returns. A completion on any other thread goes
        // on at once: the producer may be waiting, inside its call, for an effect of this very
        // completion, and making the completion wait for the call would deadlock both.
        let isOnCallingThread = attempt.callingThread === Thread.current
        if isOnCallingThread {
            attempt.deposit = result
        }
        lock.unlock()
        tracing.endInterval(attempt.interval)
        if !isOnCallingThread {
            drive(.finish(cursor, result))
        }
    }

    private func deliver(_ result: ProducerResult) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        guard let completion else { return }
        // The interval ends before the consumer runs: what the consumer does is not the run's.
        let outcome: StaticString = if case .success = result { "success" } else { "failure" }
        tracing.endInterval(interval, .label(outcome))
        completion(result)
    }

    /// The number of the attempt at `cursor`, which is the label of its success. `base` and
    /// `cursor` never change, so no lock is needed here.
    private func label(of cursor: Cursor) -> UInt {
        base.saturatingAdd(cursor.failed)
    }

    /// A count as a signpost carries it. One above the range of the signpost number stays at the
    /// largest value.
    private static func detail(_ count: UInt) -> TraceDetail {
        .number(Int64(clamping: count))
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
