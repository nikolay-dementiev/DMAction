import DMAction
import DMActionExample

/// Records the failure count of every request and answers with the action it was given.
@MainActor
final class OutcomeActionFactorySpy: OutcomeActionFactory {
    /// The failure count of every request, in order.
    private(set) var requestedFailureCounts: [Int] = []
    var action: any DMAction = DMButtonAction { $0(.success("spy")) }

    func makeAction(failingFetches failures: Int) -> any DMAction {
        requestedFailureCounts.append(failures)
        return action
    }
}
