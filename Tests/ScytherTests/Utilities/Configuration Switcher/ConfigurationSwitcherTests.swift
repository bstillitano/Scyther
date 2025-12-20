//
//  File.swift
//
//
//  Created by Brandon Stillitano on 15/1/21.
//

@testable import Scyther
import XCTest

class ConfigurationSwitcherTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override class func tearDown() {
        super.tearDown()
    }

    func testDefaultsKey() async {
        let defaultsKey = await ConfigurationSwitcher.instance.defaultsKey
        XCTAssertEqual("configuration_switcher_identity", defaultsKey)
    }

    func testEnvironmentVariables() async {
        let environmentVariables = await ConfigurationSwitcher.instance.environmentVariables
        XCTAssertTrue(environmentVariables.isEmpty)
    }

    func testConfigureEnvironmentNoVariables() async {
        await ConfigurationSwitcher.instance.configureEnvironment(withIdentifier: "UNIT_TEST")
        let configurations = await ConfigurationSwitcher.instance.configurations
        XCTAssertFalse(configurations.isEmpty)
    }

    func testConfigureDuplicateEnvironmentNoVariables() async {
        await ConfigurationSwitcher.instance.configureEnvironment(withIdentifier: "UNIT_TEST_DUPLICATE")
        await ConfigurationSwitcher.instance.configureEnvironment(withIdentifier: "UNIT_TEST_DUPLICATE")
        let configurations = await ConfigurationSwitcher.instance.configurations
        XCTAssertTrue(configurations.filter( { $0.id == "UNIT_TEST_DUPLICATE" }).count == 1)
    }
}
