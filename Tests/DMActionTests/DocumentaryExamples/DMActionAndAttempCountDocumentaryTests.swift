//
//  DMAction
//
//  Created by Mykola Dementiev
//

import XCTest
@testable import DMAction

final class DMActionAndAttempCountDocumentaryTests: XCTestCase {
    
    func testUnwrapTheOriginalResultValueThatWasPassedViaActionTypesCompletionClosure() {
        let successResult: Result<Copyable, Error> = .success(DMActionResultValue(value: PlaceholderCopyable(),
                                                                                  attemptCount: 3))
        let unwrappedSuccessResult = successResult.unwrapValue()
        
        let failureResult: Result<Copyable, Error> = .failure(NSError(domain: "TestError",
                                                                      code: 1,
                                                                      userInfo: nil))
        let unwrappedFailureResult = failureResult.unwrapValue()
        
        switch unwrappedSuccessResult {
        case .success(let value):
            XCTAssertTrue(value is PlaceholderCopyable,
                          "Value must be of type DMActionResultValue")
        default:
            XCTFail("Only success case is supported")
        }
        
        switch unwrappedFailureResult {
        case .failure(let error):
            XCTAssertTrue((error as Any) is NSError,
                           "Error must be `NSError`")
        default:
            XCTFail("Only failure case is supported")
        }
    }
}
