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
        
        XCTAssertTrue(buttonPressed)
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
        
        XCTAssertTrue(viewTapped)
    }
}
