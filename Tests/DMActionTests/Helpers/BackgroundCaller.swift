import Foundation

/// Runs a closure on a new thread, the way a callback-based system API calls back.
/// `URLSession`, for one, calls a task's completion handler on the session's delegate queue,
/// a serial queue of its own unless the session is given another (Apple documentation of
/// `URLSession.init(configuration:delegate:delegateQueue:)`).
///
/// The released API hands a producer a completion that is not `Sendable`, so no checked
/// Swift API accepts it for another thread: not `Thread.detachNewThread`, not a dispatch
/// queue, not a task. Fixtures/Rejected pins that. A producer written in Objective-C or
/// in the Swift 5 language mode still completes from other threads, and the library has
/// to behave when it does.
///
/// `Thread.detachNewThreadSelector(_:toTarget:with:)` is an Objective-C entry point of
/// Foundation that takes its target as `Any`, which the compiler does not check. So this
/// type is an unchecked hand-off, on purpose and in test code only.
///
/// What keeps a test that uses it free of a data race: the closure is handed over once,
/// the creating thread never touches it again, and the test reads what the closure wrote
/// only after waiting for an expectation that the closure fulfils last.
final class BackgroundCaller: NSObject {
    private let work: () -> Void
    /// The thread the closure runs on. Set before the closure starts.
    private(set) var thread: Thread?

    init(_ work: @escaping () -> Void) {
        self.work = work
    }

    func start() {
        Thread.detachNewThreadSelector(#selector(run), toTarget: self, with: nil)
    }

    @objc private func run() {
        thread = Thread.current
        work()
    }
}
