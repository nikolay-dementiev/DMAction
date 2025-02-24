//
//  DMAction
//
//  Created by Mykola Dementiev
//

import XCTest
@testable import DMAction

final class DMActionExtensionDocumentaryTests: XCTestCase {
    
    func testSimplifiedVersionOfTheActionThatIgnoresTheResult() {
        let execExpectation = expectation(description: "Action should be executed")
        let action: DMAction = DMButtonAction { completion in
            let textToPrint = "Action successfully done!"
            print(textToPrint)
            
            execExpectation.fulfill()
            completion(.success(textToPrint))
        }
        
        action.simpleAction()
        
        wait(for: [execExpectation], timeout: 0.001)
    }
    
    func testReturnsANewActionThatFallsBackToTheGivenActionIfThisActionFails () {
        let execExpectation1 = expectation(description: "Action 1 should be executed")
        let execExpectation2 = expectation(description: "Action 2 should be executed")
        let action1: DMAction = DMButtonAction { completion in
            let textToPrint = "Action 1 error"
            print(textToPrint)
            
            execExpectation1.fulfill()
            completion(.failure(NSError(domain: textToPrint, code: 1, userInfo: nil)))
        }
        let action2: DMAction = DMButtonAction { completion in
            let textToPrint = "Action 2 successfully done!"
            print(textToPrint)
            
            execExpectation2.fulfill()
            completion(.success(textToPrint))
        }
        let actionWithFallback = action1.fallbackTo(action2)
        
        let execExpectationResult = expectation(description: "The result of the action chain should be `Success`")
        actionWithFallback.action { result in
            switch result {
            case .success:
                execExpectationResult.fulfill()
            default:
                XCTFail("Only `Success` case designed as a Result for this action chain")
            }
        }
        
        wait(for: [execExpectation1,
                   execExpectation2,
                   execExpectationResult], timeout: 0.001)
    }
    
    func testReturnsANewActionThatRetriesThisActionTheSpecifiedNumberOfTimes() {
        let action: DMAction = DMButtonAction { completion in
            let textToPrint = "Action 1 error"
            print(textToPrint)
            
            completion(.failure(NSError(domain: textToPrint, code: 1, userInfo: nil)))
        }
        
        let actionWithRetries = action.retry(3)
        
        let expectation = self.expectation(description: "Action with retries completes")
        
        actionWithRetries.action { result in
            switch result {
            case .failure:
                expectation.fulfill()
            default:
                XCTFail("Only `Failure` case designed as a Result for this action chain")
            }
        }
        
        wait(for: [expectation], timeout: 0.001)
    }
    
    func testPerformsTheActionAndCallsTheCompletionHandlerWithTheResult() {
        let actionToExecute: DMAction = DMButtonAction { completion in
            let textToPrint = "Action 1 error"
            print(textToPrint)
            
            completion(.failure(NSError(domain: textToPrint, code: 1, userInfo: nil)))
        }
        
        let expectation = self.expectation(description: "Action completes")
        
        /** without `.action` **/
        actionToExecute { result in
            switch result {
            case .failure:
                expectation.fulfill()
            default:
                XCTFail("Only `Failure` case designed as a Result for this action chain")
            }
        }
        
        wait(for: [expectation], timeout: 0.001)
    }
}
