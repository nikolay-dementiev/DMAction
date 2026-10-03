import Foundation

/// A thread that runs the closures handed to it one after another, in the order they came,
/// the way a serial queue runs its work, on a stack of the given size.
///
/// Like `BackgroundCaller`, it is an unchecked hand-off, in test code only. A closure goes in
/// under the lock and only this thread takes it out and runs it, so no closure is ever touched
/// by two threads at the same time.
final class SerialThread: NSObject {
    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var stopped = false
    private let stackSize: Int

    init(stackSize: Int) {
        self.stackSize = stackSize
    }

    /// Starts the thread and returns it. The thread keeps this object until it stops.
    ///
    /// The thread runs at the user-initiated quality of service: on a loaded machine, a thread
    /// at the default level can wait for a processor long enough to fail a test that waits for it.
    func start() -> Thread {
        let thread = Thread(target: self, selector: #selector(run), object: nil)
        thread.stackSize = stackSize
        thread.qualityOfService = .userInitiated
        thread.start()
        return thread
    }

    func enqueue(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    /// The thread ends once it has run every job handed to it before this call.
    func stop() {
        condition.lock()
        stopped = true
        condition.signal()
        condition.unlock()
    }

    @objc private func run() {
        while let job = nextJob() {
            job()
        }
    }

    private func nextJob() -> (() -> Void)? {
        condition.lock()
        defer { condition.unlock() }
        while jobs.isEmpty && !stopped {
            condition.wait()
        }
        return jobs.isEmpty ? nil : jobs.removeFirst()
    }
}
