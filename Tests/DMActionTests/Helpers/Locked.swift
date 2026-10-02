import Foundation

/// A value that several threads may read and change at the same time, always under its lock.
final class Locked<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Answer>(_ body: (inout Value) -> Answer) -> Answer {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
