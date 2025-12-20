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
    
    func testDefaultsKey() {
        XCTAssertEqual("configuration_switcher_identity", ConfigurationSwitcher.instance.defaultsKey)
    }
    
    func testEnvironmentVariables() {
        XCTAssertTrue(ConfigurationSwitcher.instance.environmentVariables.isEmpty)
    }
    
    func testConfigureEnvironmentNoVariables() {
        ConfigurationSwitcher.instance.configureEnvironment(withIdentifier: "UNIT_TEST")
        XCTAssertFalse(ConfigurationSwitcher.instance.configurations.isEmpty)
    }
    
    func testConfigureDuplicateEnvironmentNoVariables() {
        ConfigurationSwitcher.instance.configureEnvironment(withIdentifier: "UNIT_TEST_DUPLICATE")
        ConfigurationSwitcher.instance.configureEnvironment(withIdentifier: "UNIT_TEST_DUPLICATE")
        XCTAssertTrue(ConfigurationSwitcher.instance.configurations.filter( { $0.id == "UNIT_TEST_DUPLICATE" }).count == 1)
    }
}
