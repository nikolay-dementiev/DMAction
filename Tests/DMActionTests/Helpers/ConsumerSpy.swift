import DMAction

/// The consumer side of a run: records every delivery.
final class ConsumerSpy {
    private(set) var deliveries: [DMButtonAction.ResultType] = []
    private let log: EventLog?

    init(log: EventLog? = nil) {
        self.log = log
    }

    var count: Int { deliveries.count }
    var lastLabel: UInt? { deliveries.last?.attemptCount }

    /// The last delivered payload after unwrapping, when it is a string.
    var lastValue: String? {
        deliveries.last.flatMap(Self.text(of:))
    }

    /// The last success value exactly as it was delivered, before any unwrapping.
    var lastDelivered: (any Copyable)? {
        guard case .success(let value)? = deliveries.last else { return nil }
        return value
    }

    var lastError: (any Error)? {
        guard case .failure(let error)? = deliveries.last else { return nil }
        return error
    }

    func receive(_ result: DMButtonAction.ResultType) {
        deliveries.append(result)
        log?.add("consumer")
    }

    /// The payload of a success after unwrapping, when it is a string.
    static func text(of result: DMButtonAction.ResultType) -> String? {
        guard case .success(let value) = result.unwrapValue() else { return nil }
        return value as? String
    }
}
