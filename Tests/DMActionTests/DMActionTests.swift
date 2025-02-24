//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import XCTest
@testable import DMAction

final class DMActionTests: XCTestCase {
    
    // MARK: DMButtonAction
    
    func testDMActionResultValueProtocolEmptyAttemptCount() throws {
        let newValue = MockCopyable(value: "DMActionResultValueProtocolEmptyAttemptCount")
        
        XCTAssertNil(newValue.attemptCount, "DMActionResultValueProtocol's attemptCount should be `nil`")
    }
    
    func testDMButtonActionInitialization() {
        // Initialize with ActionType
        let buttonAction = DMButtonAction { completion in
            completion(.success(MockCopyable(value: "Success")))
        }
        
        XCTAssertEqual(buttonAction.currentAttempt, 0, "Initial attempt should be 0")
        XCTAssertNotNil(buttonAction.id, "ID should be generated")
        
        // Execute the action
        var attemptExecuted: UInt?
        var result: DMAction.ResultType?
        buttonAction { output in
            result = output.unwrapValue()
            attemptExecuted = output.attemptCount
        }
        
        XCTAssertEqual(attemptExecuted,
                       buttonAction.currentAttempt,
                       "The number of attempts made does not match the required number.")
        
        if case .success(let copyable) = result {
            XCTAssertEqual((copyable as? MockCopyable)?.value, "Success", "Action should complete successfully")
        } else {
            XCTFail("Action did not complete successfully")
        }
    }

    func testDMButtonActionWithSimpleAction() {
        var wasCalled = false
        let buttonAction = DMButtonAction {
            wasCalled = true
        }
        
        // Execute the simple action
        buttonAction.simpleAction()
        XCTAssertTrue(wasCalled, "Simple action should be executed")
    }
    
    // MARK: DMActionWithFallback
    
    func testDMActionWithFallbackInitializationFailurePrimaryAction() {
        // Primary action
        let primaryButtonAction = DMButtonAction { completion in
            completion(.failure(NSError(domain: "TestError", code: 1, userInfo: nil)))
        }
        
        // Fallback action
        let fallbackButtonAction = DMButtonAction { completion in
            completion(.success(MockCopyable(value: "Fallback Success")))
        }
        
        // Create DMActionWithFallback
        let actionWithFallback = primaryButtonAction
            .retry(1)
            .fallbackTo(fallbackButtonAction)
        
        XCTAssertNotNil(actionWithFallback.id, "ID should be generated")
        
        // Execute the action
        var result: DMAction.ResultType?
        var attemptExecuted: UInt?
        actionWithFallback { output in
            result = output.unwrapValue()
            attemptExecuted = output.attemptCount
        }
        
        XCTAssertEqual(attemptExecuted,
                       3,
                       "The number of attempts made does not match the required number.")
        
        if case .success(let copyable) = result {
            XCTAssertEqual((copyable as? MockCopyable)?.value, "Fallback Success", "Fallback action should execute on failure")
        } else {
            XCTFail("Fallback action did not execute successfully")
        }
    }
    
    func testDMActionWithFallbackInitializationSuccessPrimaryAction() {
        // Primary action
        let primaryButtonAction = DMButtonAction { completion in
            completion(.success(MockCopyable(value: "PrimaryAction Success")))
        }
        
        // Fallback action
        let fallbackButtonAction = DMButtonAction { completion in
            completion(.success(MockCopyable(value: "Fallback Success")))
        }
        
        // Create DMActionWithFallback
        let actionWithFallback = primaryButtonAction
            .retry(1)
            .fallbackTo(fallbackButtonAction)
        
        XCTAssertNotNil(actionWithFallback.id, "ID should be generated")
        
        // Execute the action
        var result: DMAction.ResultType?
        var attemptExecuted: UInt?
        actionWithFallback { output in
            result = output.unwrapValue()
            attemptExecuted = output.attemptCount
        }
        
        XCTAssertEqual(attemptExecuted,
                       0,
                       "The number of attempts made does not match the required number.")
        
        if case .success(let copyable) = result {
            XCTAssertEqual((copyable as? MockCopyable)?.value,
                           "PrimaryAction Success",
                           "PrimaryAction action should execute firstly")
        } else {
            XCTFail("Fallback action did not execute successfully")
        }
    }
    
    // MARK: simpleAction
    
    func testSimpleActionExtension() {
        var wasCalled = false
        let buttonAction = DMButtonAction {
            wasCalled = true
        }
        
        // Use the `simpleAction` extension
        buttonAction.simpleAction()
        XCTAssertTrue(wasCalled, "Simple action should be executed via the extension")
    }
    
    // MARK: fallbackTo(_:)
    
    func testFallbackTo() {
        // Primary action
        let primaryAction: DMAction.ActionType = { completion in
            completion(.failure(NSError(domain: "TestError", code: 1, userInfo: nil)))
        }
        
        // Fallback action
        let fallbackAction: DMAction.ActionType = { completion in
            completion(.success(MockCopyable(value: "Fallback Success")))
        }
        
        // Create DMActionWithFallback using `fallbackTo`
        let initialAction = DMButtonAction(primaryAction)
        let actionWithFallback = initialAction
            .retry(3)
            .fallbackTo(DMButtonAction(fallbackAction))
        
        // Execute the action
        var result: DMAction.ResultType?
        var attemptExecuted: UInt?
        actionWithFallback { output in
            result = output.unwrapValue()
            attemptExecuted = output.attemptCount
        }
        
        XCTAssertEqual(attemptExecuted,
                       5,
                       "The number of attempts made does not match the required number.")
        
        if case .success(let copyable) = result {
            XCTAssertEqual((copyable as? MockCopyable)?.value, "Fallback Success", "Fallback action should execute on failure")
        } else {
            XCTFail("Fallback action did not execute successfully")
        }
    }
}

// MARK: - Helpers

struct MockCopyable: DMActionResultValueProtocol {
    let value: String
}
