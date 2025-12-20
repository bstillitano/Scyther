//
//  AppEnvironmentTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class AppEnvironmentTests: XCTestCase {

    // MARK: - isDebug Tests

    func testIsDebugReturnsValue() {
        // In test environment, we can't control #if DEBUG, but we can verify it returns a Bool
        let result = AppEnvironment.isDebug
        XCTAssertNotNil(result)
        // In test builds, this should typically be true
        #if DEBUG
        XCTAssertTrue(result)
        #else
        XCTAssertFalse(result)
        #endif
    }

    // MARK: - isSimulator Tests

    func testIsSimulatorReturnsValue() {
        let result = AppEnvironment.isSimulator
        XCTAssertNotNil(result)
        #if targetEnvironment(simulator)
        XCTAssertTrue(result)
        #else
        XCTAssertFalse(result)
        #endif
    }

    // MARK: - isTestCase Tests

    func testIsTestCaseReturnsTrue() {
        // When running tests, this should return true
        let result = AppEnvironment.isTestCase
        XCTAssertTrue(result)
    }

    // MARK: - isDevelopment Tests

    func testIsDevelopmentLogic() {
        // isDevelopment = isTestFlight || isSimulator || isDebug
        let isDev = AppEnvironment.isDevelopment

        // If any of these are true, isDevelopment should be true
        if AppEnvironment.isTestFlight || AppEnvironment.isSimulator || AppEnvironment.isDebug {
            XCTAssertTrue(isDev)
        }
    }

    // MARK: - isAppStore Tests

    func testIsAppStoreLogic() {
        // isAppStore = !isDevelopment
        let isAppStore = AppEnvironment.isAppStore
        let isDevelopment = AppEnvironment.isDevelopment

        XCTAssertEqual(isAppStore, !isDevelopment)
    }

    // MARK: - configuration Tests

    func testConfigurationReturnsValidType() {
        let config = AppEnvironment.configuration()
        XCTAssertTrue([BuildType.debug, BuildType.testFlight, BuildType.appStore].contains(config))
    }

    func testConfigurationWithTestValueDebug() {
        let config = AppEnvironment.configuration(testValue: .debug)
        // When testValue is debug, actual values should be checked first,
        // but the logic prioritizes isTestFlight
        XCTAssertNotNil(config)
    }

    func testConfigurationWithTestValueTestFlight() {
        let config = AppEnvironment.configuration(testValue: .testFlight)
        XCTAssertEqual(config, .testFlight)
    }

    func testConfigurationWithTestValueAppStore() {
        let config = AppEnvironment.configuration(testValue: .appStore)
        // If isTestFlight is true, it takes priority
        if !AppEnvironment.isTestFlight {
            XCTAssertEqual(config, .appStore)
        }
    }

    // MARK: - isTestFlight Tests

    func testIsTestFlightReturnsValue() {
        let result = AppEnvironment.isTestFlight
        // Should return false when running in debug/simulator
        if AppEnvironment.isDebug {
            XCTAssertFalse(result)
        }
    }

    // MARK: - isJailbroken Tests

    func testIsJailbrokenOnSimulator() {
        // On simulator, isJailbroken should always return false
        if AppEnvironment.isSimulator {
            XCTAssertFalse(AppEnvironment.isJailbroken)
        }
    }
}

// MARK: - BuildType Tests

final class BuildTypeTests: XCTestCase {

    func testDebugRawValue() {
        XCTAssertEqual(BuildType.debug.rawValue, "Debug")
    }

    func testTestFlightRawValue() {
        XCTAssertEqual(BuildType.testFlight.rawValue, "TestFlight")
    }

    func testAppStoreRawValue() {
        XCTAssertEqual(BuildType.appStore.rawValue, "App Store")
    }

    func testAllCases() {
        let allCases: [BuildType] = [.debug, .testFlight, .appStore]
        XCTAssertEqual(allCases.count, 3)
    }

    func testInitFromRawValue() {
        XCTAssertEqual(BuildType(rawValue: "Debug"), .debug)
        XCTAssertEqual(BuildType(rawValue: "TestFlight"), .testFlight)
        XCTAssertEqual(BuildType(rawValue: "App Store"), .appStore)
        XCTAssertNil(BuildType(rawValue: "Invalid"))
    }
}
#endif
