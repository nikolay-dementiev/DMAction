import XCTest
import UIKit

extension XCTestCase {
    @MainActor
    func perform(event: UIControl.Event,
                 from button: UIControl,
                 target: NSObject,
                 args: Any?) {
        let action = button.actions(forTarget: target, 
                                    forControlEvent: event)?.first ?? ""
        target.performSelector(onMainThread: Selector(action),
                               with: args,
                               waitUntilDone: true)
    }

    @MainActor
    func performGestureRecognizer<T>(type: T.Type,
                                     on view: UIView) {
        let selectorString = getGestureRecognizerSelectorString(type: type,
                                                                on: view)

        view.perform(.init(stringLiteral: selectorString))
    }
    
    @MainActor
    func performGestureRecognizer<T>(type: T.Type,
                                     on viewController: UIViewController) {
        let selectorString = getGestureRecognizerSelectorString(type: type,
                                                                on: viewController.view)

        viewController.perform(.init(stringLiteral: selectorString))
    }
    
    @MainActor
    private func getGestureRecognizerSelectorString<T>(type: T.Type,
                                                       on view: UIView) -> String {
        let gesture = view.gestureRecognizers?.first { $0 is T }

        let target = (gesture?.value(forKey: "_targets") as? [NSObject])?.first
        let selectorString = String(describing: target)
            .components(separatedBy: ", ")
            .first?
            .replacingOccurrences(of: "(action=", with: "")
            .replacingOccurrences(of: "Optional(", with: "")
            ?? ""
        
        return selectorString
    }
}
