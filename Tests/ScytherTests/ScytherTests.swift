import XCTest
@testable import Scyther

final class ScytherTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
//        XCTAssertEqual(Scyther().text, "Hello, World!")
        XCTAssertFalse(MobileDevices.plistData?.isEmpty ?? true)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
