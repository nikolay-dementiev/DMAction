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
/// `Thread.init(target:selector:object:)` is an Objective-C entry point of Foundation that
/// takes its target as `Any`, which the compiler does not check. So this type is an
/// unchecked hand-off, on purpose and in test code only.
///
/// What keeps a test that uses it free of a data race: the closure is handed over once,
/// the creating thread never touches it again, and the test reads what the closure wrote
/// only after waiting for a signal the closure sends last: an expectation it fulfils, or a
/// dispatch group it leaves.
///
/// `stackSize` gives the thread a stack of that many bytes. 512 KB is what a secondary
/// thread gets by default (Apple's Threading Programming Guide, Thread Management).
final class BackgroundCaller: NSObject {
    private let work: () -> Void
    private let stackSize: Int?
    private let qualityOfService: QualityOfService?
    /// The thread the closure runs on. Set before the thread starts.
    private(set) var thread: Thread?

    /// `qualityOfService` sets the thread's level; `nil` leaves the default.
    init(stackSize: Int? = nil, qualityOfService: QualityOfService? = nil, _ work: @escaping () -> Void) {
        self.stackSize = stackSize
        self.qualityOfService = qualityOfService
        self.work = work
    }

    func start() {
        let thread = Thread(target: self, selector: #selector(run), object: nil)
        if let stackSize {
            thread.stackSize = stackSize
        }
        if let qualityOfService {
            thread.qualityOfService = qualityOfService
        }
        self.thread = thread
        thread.start()
    }

    @objc private func run() {
        work()
    }
}
