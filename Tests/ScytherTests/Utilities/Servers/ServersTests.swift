//
//  ServersTests.swift
//
//
//  Created by Brandon Stillitano on 15/1/21.
//

@testable import Scyther
import XCTest

class ServersTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override class func tearDown() {
        super.tearDown()
    }

    func testVariablesEmpty() async {
        let variables = await Scyther.servers.variables
        XCTAssertTrue(variables.isEmpty)
    }

    func testRegisterEnvironmentNoVariables() async {
        await Scyther.servers.register(id: "UNIT_TEST")
        let all = await Scyther.servers.all
        XCTAssertFalse(all.isEmpty)
    }

    func testRegisterDuplicateEnvironmentNoVariables() async {
        await Scyther.servers.register(id: "UNIT_TEST_DUPLICATE")
        await Scyther.servers.register(id: "UNIT_TEST_DUPLICATE")
        let all = await Scyther.servers.all
        XCTAssertTrue(all.filter({ $0.id == "UNIT_TEST_DUPLICATE" }).count == 1)
    }
}
