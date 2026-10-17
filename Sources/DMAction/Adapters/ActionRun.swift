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
                    // A label a producer put on its success is replaced: the run counts its own
                    // attempts. `base` and `cursor` never change, so no lock is needed here.
                    deliver(DMActionResultValue.labelling(result, attempt: base.saturatingAdd(cursor.failed)))
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

    private func complete(_ attempt: Attempt, with result: ProducerResult) {
        lock.lock()
        guard let cursor = attempt.cursor else {
            lock.unlock()
            Self.reportIgnoredCompletion()
            return
        }
        attempt.cursor = nil
        // A completion on the thread that is still inside the producer call is kept for that
        // thread, which goes on when the call returns. A completion on any other thread goes
        // on at once: the producer may be waiting, inside its call, for an effect of this very
        // completion, and making the completion wait for the call would deadlock both.
        if attempt.callingThread === Thread.current {
            attempt.deposit = result
            lock.unlock()
            return
        }
        lock.unlock()
        drive(.finish(cursor, result))
    }

    private func deliver(_ result: ProducerResult) {
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
