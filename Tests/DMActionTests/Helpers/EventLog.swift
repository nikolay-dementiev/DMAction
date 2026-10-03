/// An ordered record of what happened, shared by the spies of one test.
final class EventLog {
    private(set) var events: [String] = []

    func add(_ event: String) {
        events.append(event)
    }
}
