import DMAction
import Foundation

/// Keeps the completions that producers received, so that a test can call them later, from any
/// thread. An unchecked hand-off, in test code only: every access is under the lock.
final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [(DMAction.ResultType) -> Void] = []

    func record(_ completion: @escaping (DMAction.ResultType) -> Void) {
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions.count
    }

    /// Calls the completion that producer call `index` received, outside the lock.
    func complete(_ result: DMAction.ResultType, at index: Int = 0) {
        lock.lock()
        let completion = completions[index]
        lock.unlock()
        completion(result)
    }
}

/// Counts the calls of a mapper, which is `@Sendable` and runs on the thread of the callback.
/// An unchecked hand-off, in test code only: every access is under the lock.
final class MapCounter: @unchecked Sendable {
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
