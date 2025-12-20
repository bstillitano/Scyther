//
//  ServerConfigurationTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class ServerConfigurationTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization() {
        let config = ServerConfiguration(id: "Development")
        XCTAssertEqual(config.id, "Development")
        XCTAssertTrue(config.variables.isEmpty)
    }

    func testInitializationWithVariables() {
        var config = ServerConfiguration(id: "Production")
        config.variables = [
            "API_URL": "https://api.example.com",
            "ENABLE_LOGGING": "true"
        ]

        XCTAssertEqual(config.id, "Production")
        XCTAssertEqual(config.variables.count, 2)
        XCTAssertEqual(config.variables["API_URL"], "https://api.example.com")
        XCTAssertEqual(config.variables["ENABLE_LOGGING"], "true")
    }

    // MARK: - Identifiable Conformance Tests

    func testIdentifiableConformance() {
        let config = ServerConfiguration(id: "Staging")
        XCTAssertEqual(config.id, "Staging")
    }

    // MARK: - Variables Tests

    func testEmptyVariables() {
        let config = ServerConfiguration(id: "Test")
        XCTAssertTrue(config.variables.isEmpty)
        XCTAssertEqual(config.variables.count, 0)
    }

    func testVariableAccess() {
        var config = ServerConfiguration(id: "Test")
        config.variables["KEY1"] = "value1"
        config.variables["KEY2"] = "value2"

        XCTAssertEqual(config.variables["KEY1"], "value1")
        XCTAssertEqual(config.variables["KEY2"], "value2")
        XCTAssertNil(config.variables["KEY3"])
    }

    func testVariableModification() {
        var config = ServerConfiguration(id: "Test")
        config.variables["API_URL"] = "https://old.example.com"
        XCTAssertEqual(config.variables["API_URL"], "https://old.example.com")

        config.variables["API_URL"] = "https://new.example.com"
        XCTAssertEqual(config.variables["API_URL"], "https://new.example.com")
    }

    func testVariableDeletion() {
        var config = ServerConfiguration(id: "Test")
        config.variables["KEY"] = "value"
        XCTAssertNotNil(config.variables["KEY"])

        config.variables["KEY"] = nil
        XCTAssertNil(config.variables["KEY"])
    }

    // MARK: - ID Mutation Tests

    func testIdMutation() {
        var config = ServerConfiguration(id: "Initial")
        XCTAssertEqual(config.id, "Initial")

        config.id = "Updated"
        XCTAssertEqual(config.id, "Updated")
    }

    // MARK: - Common Scenarios Tests

    func testDevelopmentConfiguration() {
        var devConfig = ServerConfiguration(id: "Development")
        devConfig.variables = [
            "API_URL": "https://dev-api.example.com",
            "DEBUG_MODE": "true",
            "LOG_LEVEL": "verbose"
        ]

        XCTAssertEqual(devConfig.id, "Development")
        XCTAssertEqual(devConfig.variables["API_URL"], "https://dev-api.example.com")
        XCTAssertEqual(devConfig.variables["DEBUG_MODE"], "true")
        XCTAssertEqual(devConfig.variables["LOG_LEVEL"], "verbose")
    }

    func testStagingConfiguration() {
        var stagingConfig = ServerConfiguration(id: "Staging")
        stagingConfig.variables = [
            "API_URL": "https://staging-api.example.com",
            "DEBUG_MODE": "false",
            "LOG_LEVEL": "info"
        ]

        XCTAssertEqual(stagingConfig.id, "Staging")
        XCTAssertEqual(stagingConfig.variables.count, 3)
    }

    func testProductionConfiguration() {
        var prodConfig = ServerConfiguration(id: "Production")
        prodConfig.variables = [
            "API_URL": "https://api.example.com",
            "DEBUG_MODE": "false",
            "LOG_LEVEL": "error"
        ]

        XCTAssertEqual(prodConfig.id, "Production")
        XCTAssertEqual(prodConfig.variables["DEBUG_MODE"], "false")
    }

    // MARK: - Sendable Conformance Tests

    func testSendableConformance() async {
        let config = ServerConfiguration(id: "Test")

        // Test that we can pass the config across concurrency boundaries
        await Task {
            XCTAssertEqual(config.id, "Test")
        }.value
    }
}
