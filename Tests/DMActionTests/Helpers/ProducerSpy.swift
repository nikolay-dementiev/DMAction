import DMAction

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

    /// Succeeds on the given call and fails on every call before it, each time with an
    /// error of its own. `nil`: fails on every call.
    static func succeeding(onCall call: Int?, with value: any Copyable = "value") -> ProducerSpy {
        guard let call else { return alwaysFailing() }
        let failures = (1..<max(call, 1)).map { _ in Outcome.failure(MarkedError()) }
        return ProducerSpy(script: failures + [.success(value)])
    }

    /// Fails on every call with the same error.
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
