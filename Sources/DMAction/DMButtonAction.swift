//
//  DMAction
//
//  Created by Mykola Dementiev
//

import Foundation

/// An action made of one producer.
///
/// Every run of it, through ``action``, call syntax or ``DMAction/simpleAction``, is guarded:
/// the first completion wins and the result is delivered at most once, labelled with
/// ``currentAttempt``, which is 0.
///
/// A producer that reports a result:
///
/// ```swift
/// let load = DMButtonAction { completion in
///     URLSession.shared.dataTask(with: url) { data, _, error in
///         if let data {
///             completion(.success(data))
///         } else {
///             completion(.failure(error ?? URLError(.unknown)))
///         }
///     }
///     .resume()
/// }
///
/// load { result in
///     switch result.unwrapValue() {
///     case .success(let data):
///         print(data) // the Data the producer delivered, out of its wrapper
///     case .failure(let error):
///         print(error)
///     }
/// }
/// ```
///
/// A closure that cannot fail:
///
/// ```swift
/// let tap = DMButtonAction {
///     print("Tapped")
/// }
/// tap.simpleAction()
/// ```
public struct DMButtonAction: DMAction {
    /// Settings used for the default attempt count.
    private enum Settings {
        static let defaultAttemptCount: UInt = 0
    }

    /// The label of a success of this action: 0 for an action made by a public initializer.
    public let currentAttempt: UInt

    /// An identifier of this value. A copy shares it; every composition gets a new one.
    public let id: UUID = UUID()

    /// Runs the producer once, as a guarded run, and calls the given completion at most once
    /// with its result. A success is labelled ``currentAttempt``.
    public let action: ActionType

    /// What `action` runs.
    let plan: ActionPlan

    /// Initializes a new instance of `DMButtonAction` with the specified current attempt and action.
    ///
    /// - Parameters:
    ///   - currentAttempt: The current attempt number.
    ///   - action: The action to be performed.
    internal init(currentAttempt: UInt,
                  action: @escaping ActionType) {
        let plan = ActionPlan(.produce(action))
        self.currentAttempt = currentAttempt
        self.plan = plan
        self.action = { completion in
            plan.run(base: currentAttempt, completion)
        }
    }

    /// Creates an action from a producer.
    ///
    /// Each run calls `action` on the thread that runs it. The producer calls its completion
    /// once, before it returns or later, on any thread; a second call is ignored.
    ///
    /// - Parameter action: The producer.
    public init(_ action: @escaping ActionType) {
        self.init(currentAttempt: Settings.defaultAttemptCount,
                  action: action)
    }

    /// Creates an action from a closure that cannot fail.
    ///
    /// Each run calls `simpleAction` and succeeds with a ``PlaceholderCopyable``, so a retry or
    /// a fallback of this action never runs.
    ///
    /// - Parameter simpleAction: The closure to call on each run.
    public init(_ simpleAction: @escaping () -> Void) {
        self.init({ completion in
            simpleAction()
            completion(.success(DMActionResultValue(value: PlaceholderCopyable(),
                                                    attemptCount: Settings.defaultAttemptCount)))
        })
    }
}
