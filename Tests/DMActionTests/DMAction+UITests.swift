//
//  DMAction
//
//  Created by Mykola Dementiev
//

import XCTest
import UIKit
import SwiftUI
@testable import DMAction

final class MyViewControllerTests: XCTestCase {
    
    var resultClosure: (() -> Void)?
    
    override func tearDown() {
        super.tearDown()
        
        self.resultClosure = nil
    }

    @MainActor
    func testAddRoomButtonInRoomsViewController() {
        let viewController = MockMyViewController()
        viewController.startViewLifecycle()

        XCTAssertNotNil(viewController.button,
                        "Button Not Initialised")
        XCTAssertNotNil(viewController.button.superview,
                        "Button Not Added To View")
        
        XCTAssertNotNil(viewController.tapGesture,
                        "tapGesture Not Initialised")
    }
    
    @MainActor
    func testButtonTap() {
        let viewController = MockMyViewController()
        viewController.startViewLifecycle()
        
        var buttonPressed = false
        viewController.buttonTappedClosure = {
            buttonPressed = true
        }
        
        perform(event: .touchUpInside,
                from: viewController.button,
                target: viewController,
                args: nil)
        
        XCTAssertTrue(buttonPressed,
                      "buttonTappedClosure not called")
    }
    
    @MainActor
    func testViewTap() {
        let viewController = MockMyViewController()
        viewController.startViewLifecycle()
        
        var viewTapped = false
        viewController.viewTappedClosure = {
            viewTapped = true
        }
        
        performGestureRecognizer(type: UITapGestureRecognizer.self,
                                 on: viewController)
        
        XCTAssertTrue(viewTapped,
                      "viewTappedClosure not called")
    }
    
    @MainActor
    func testBaseDMActionWithUIButton() {
        let buttonTest = UIButton(type: .system)
        buttonTest.addTarget(self,
                             action: #selector(buttonTestActionWithHandledResult),
                             for: .touchUpInside)
        
        var viewTapped = false
        resultClosure = {
            viewTapped = true
        }
        
        perform(event: .touchUpInside,
                from: buttonTest,
                target: self,
                args: nil)
        
        XCTAssertTrue(viewTapped,
                      "ButtonTest not called")
    }
    
    @MainActor
    func testBaseDMActionWithUIButton1() {
        let buttonTest = UIButton(type: .system)
        buttonTest.addTarget(self,
                             action: #selector(buttonTestActionWithMutedResult),
                             for: .touchUpInside)
        
        perform(event: .touchUpInside,
                from: buttonTest,
                target: self,
                args: nil)
    }
    
    @objc
    func buttonTestActionWithHandledResult() {
        let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
        let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)
        
        primaryButtonAction
            .retry(2)
            // swiftlint:disable:next empty_parentheses_with_trailing_closure
            .fallbackTo(fallbackButtonAction)() { [weak self] output in
                // `unwrapValue()`: get rid of the wrapper - return the original result
                // value that was passed via DMButtonAction' completion closure
                print("the result value: \(output.unwrapValue())")
                // `attemptCount`: contains UInt number of action's attemps
                print("attemptCount: \(String(describing: output.attemptCount))")
                
                self?.resultClosure?()
            }
    }
    
    @objc
    func buttonTestActionWithMutedResult() {
        let primaryButtonAction = DMButtonAction(makeActionWithFailureResult)
        let fallbackButtonAction = DMButtonAction(makeActionWithSuccessResult)
        
        primaryButtonAction
            .retry(2)
            .fallbackTo(fallbackButtonAction)
            .simpleAction()
    }
    
    func makeActionWithFailureResult(completion: @escaping (DMButtonAction.ResultType) -> Void) {
        
        // ... do something
        
        completion(.failure(NSError(domain: "TestDomain",
                                    code: 404,
                                    userInfo: nil)))
    }
    func makeActionWithSuccessResult(completion: @escaping (DMButtonAction.ResultType) -> Void) {
        
        // ... do something
        
        let yourResultVaue: Copyable = "\(#function) succeded!"
        completion(.success(yourResultVaue))
    }
}
