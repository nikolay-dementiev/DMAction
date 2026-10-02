import DMAction
import Foundation

/// An ordered record of what happened, shared by the spies of one test.
final class EventLog {
    private(set) var events: [String] = []

    func add(_ event: String) {
        events.append(event)
    }
}

/// An error that is recognised by identity, not by value.
final class MarkedError: Error {}

/// A producer that plays a script and records how it was called.
final class ProducerSpy {
    enum Outcome {
        case success(any Copyable)
        case failure(any Error)
        /// Keep the completion and return without calling it.
        case hold
    }

    private(set) var callCount = 0
    private(set) var heldCompletions: [(DMButtonAction.ResultType) -> Void] = []
    private let name: String
    private let log: EventLog?
    private let script: [Outcome]

    /// Call n plays entry n of the script. The last entry repeats.
    init(_ name: String = "producer", log: EventLog? = nil, script: [Outcome]) {
        self.name = name
        self.log = log
        self.script = script
    }

    /// Fails `failures` times with the given error, then succeeds with the value.
    static func failing(
        _ failures: Int,
        with error: any Error = MarkedError(),
        then value: any Copyable,
        name: String = "producer",
        log: EventLog? = nil
    ) -> ProducerSpy {
        let script = Array(repeating: Outcome.failure(error), count: failures) + [.success(value)]
        return ProducerSpy(name, log: log, script: script)
    }

    /// Fails on every call.
    static func alwaysFailing(
        with error: any Error = MarkedError(),
        name: String = "producer",
        log: EventLog? = nil
    ) -> ProducerSpy {
        ProducerSpy(name, log: log, script: [.failure(error)])
    }

    var action: DMButtonAction {
        DMButtonAction(produce)
    }

    func produce(completion: @escaping (DMButtonAction.ResultType) -> Void) {
        callCount += 1
        let call = callCount
        log?.add("\(name) call \(call)")
        switch script[min(call, script.count) - 1] {
        case .success(let value):
            completion(.success(value))
        case .failure(let error):
            completion(.failure(error))
        case .hold:
            heldCompletions.append(completion)
        }
        log?.add("\(name) return \(call)")
    }
}

/// The consumer side of a run: records every delivery.
final class ConsumerSpy {
    private(set) var deliveries: [DMButtonAction.ResultType] = []
    private let log: EventLog?

    init(log: EventLog? = nil) {
        self.log = log
    }

    var count: Int { deliveries.count }
    var lastLabel: UInt? { deliveries.last?.attemptCount }

    /// The delivered payload after unwrapping, when it is a string.
    var lastValue: String? {
        guard case .success(let value)? = deliveries.last?.unwrapValue() else { return nil }
        return value as? String
    }

    var lastError: (any Error)? {
        guard case .failure(let error)? = deliveries.last else { return nil }
        return error
    }

    func receive(_ result: DMButtonAction.ResultType) {
        deliveries.append(result)
        log?.add("consumer")
    }
}

/// Runs a closure on a new thread, the way a callback-based system API calls back.
final class BackgroundCaller: NSObject {
    private let work: () -> Void

    init(_ work: @escaping () -> Void) {
        self.work = work
    }

    func start() {
        Thread.detachNewThreadSelector(#selector(run), toTarget: self, with: nil)
    }

    @objc private func run() {
        work()
    }
}
