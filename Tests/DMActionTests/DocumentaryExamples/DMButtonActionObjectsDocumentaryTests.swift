//
//  DMAction
//
//  Created by Mykola Dementiev
//

import XCTest
@testable import DMAction

final class DMButtonActionObjectsDocumentaryTests: XCTestCase {
    
    func testExampleHowToUseDmButtonActionWithASimpleAction() {
        let buttonAction = DMButtonAction {
            print("Button action performed")
        }
        
        buttonAction.action { result in
            XCTAssertEqual(result.attemptCount,
                           0,
                           "Attempt count must be `0` for successful simple button action")
            
            switch result {
            case .success(let value):
                print("Success with value: \(value)")
                
            case .failure(let error):
                print("Failed with error: \(error)")
                XCTFail("Failure is not designed for simple button action: \(error)")
            }
        }
    }
    
    func testExampleOfHowToUseDmButtonActionWithAnActionClosure() {
        let buttonActionWithClosure = DMButtonAction { completion in
            // Perform some async task
            completion(.success(DMActionResultValue(value: PlaceholderCopyable(),
                                                    attemptCount: 0)))
        }
        
        buttonActionWithClosure.action { result in
            XCTAssertEqual(result.attemptCount,
                           0,
                           "Attempt count must be `0` for successful simple button action")
            
            switch result {
            case .success(let value):
                print("Success with value: \(value)")
            case .failure(let error):
                print("Failed with error: \(error)")
                XCTFail("Failure is not designed for this button action: \(error)")
            }
        }
    }
}
