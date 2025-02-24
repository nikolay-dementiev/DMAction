//
//  DMErrorHandling
//
//  Created by Mykola Dementiev
//

import XCTest

func XCTAssertThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String,
                        file: StaticString = #file, line: UInt = #line) {
    do {
        _ = try expression()
        XCTFail("Expression did not throw any error", file: (file), line: line)
    } catch {
        XCTAssertEqual(error.localizedDescription, message, file: (file), line: line)
    }
}
