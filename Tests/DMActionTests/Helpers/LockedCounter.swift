import Foundation

/// A count that several threads may raise at the same time. The concurrency tests count
/// with it, so that the test itself has no data race for the Thread Sanitizer to find.
final class LockedCounter {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
