import Foundation

/// Holds threads until a given number of them have arrived, then lets them go on together.
///
/// The wait has two phases. Until every party has arrived, a thread sleeps on a condition, so
/// on a loaded machine it takes no processor time from the threads it waits for; the last one
/// to arrive wakes them all with one broadcast. A woken thread runs some microseconds after
/// the one that woke it, which is long enough for that one to finish what the parties race
/// for. So each party then spins, for a few milliseconds at most, until every party runs
/// again, and they go on within about a microsecond of each other.
///
/// A thread that waits past its deadline goes on and says so, so that a test counts it
/// instead of hanging.
final class Barrier {
    /// How long a party spins, after the broadcast, for the others to run again.
    private static let lineUpNanoseconds: UInt64 = 5_000_000

    private let condition = NSCondition()
    private let parties: Int
    private var arrived = 0
    private var running = 0

    init(parties: Int) {
        self.parties = parties
    }

    /// Waits until every party has arrived, or until the deadline. Returns `false` when the
    /// deadline came first.
    func arriveAndWait(deadline: Date) -> Bool {
        condition.lock()
        arrived += 1
        if arrived == parties {
            condition.broadcast()
        }
        while arrived < parties {
            if !condition.wait(until: deadline) {
                break
            }
        }
        let everyoneArrived = arrived >= parties
        running += 1
        condition.unlock()
        guard everyoneArrived else {
            return false
        }
        let lineUpEnd = DispatchTime.now().uptimeNanoseconds + Self.lineUpNanoseconds
        while !everyoneRuns(), DispatchTime.now().uptimeNanoseconds < lineUpEnd {}
        return true
    }

    private func everyoneRuns() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return running >= parties
    }
}
