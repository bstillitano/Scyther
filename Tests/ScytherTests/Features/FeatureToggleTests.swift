//
//  FeatureToggleTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class FeatureToggleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up any stored values before each test
        cleanupUserDefaults()
    }

    override func tearDown() {
        cleanupUserDefaults()
        super.tearDown()
    }

    private func cleanupUserDefaults() {
        // Remove test-related keys
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("Scyther_toggler_local_value_") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Initialization Tests

    func testInitializationWithRemoteValueFalse() {
        let toggle = FeatureToggle(name: "Test Feature", remoteValue: false)

        XCTAssertEqual(toggle.name, "Test Feature")
        XCTAssertEqual(toggle.remoteValue, false)
    }

    func testInitializationWithRemoteValueTrue() {
        let toggle = FeatureToggle(name: "Test Feature", remoteValue: true)

        XCTAssertEqual(toggle.name, "Test Feature")
        XCTAssertEqual(toggle.remoteValue, true)
    }

    // MARK: - Name Tests

    func testNameProperty() {
        let toggle = FeatureToggle(name: "My Feature", remoteValue: true)
        XCTAssertEqual(toggle.name, "My Feature")
    }

    func testNameWithSpaces() {
        let toggle = FeatureToggle(name: "My Special Feature", remoteValue: true)
        XCTAssertEqual(toggle.name, "My Special Feature")
    }

    func testNameEmpty() {
        let toggle = FeatureToggle(name: "", remoteValue: true)
        XCTAssertEqual(toggle.name, "")
    }

    // MARK: - Remote Value Tests

    func testRemoteValueFalse() {
        let toggle = FeatureToggle(name: "Test", remoteValue: false)
        XCTAssertFalse(toggle.remoteValue)
    }

    func testRemoteValueTrue() {
        let toggle = FeatureToggle(name: "Test", remoteValue: true)
        XCTAssertTrue(toggle.remoteValue)
    }

    // MARK: - Local Value Tests

    func testLocalValueDefaultsFalse() {
        let toggle = FeatureToggle(name: "Test Local Value", remoteValue: false)
        // Local value defaults to false (UserDefaults returns false for missing bool)
        XCTAssertFalse(toggle.localValue)
    }

    func testLocalValuePersistence() {
        var toggle = FeatureToggle(name: "Persisted Feature", remoteValue: false)

        toggle.localValue = true
        XCTAssertTrue(toggle.localValue)

        // Create a new toggle with the same name - should have same local value
        let toggle2 = FeatureToggle(name: "Persisted Feature", remoteValue: false)
        XCTAssertTrue(toggle2.localValue)
    }

    func testLocalValueCanBeToggled() {
        var toggle = FeatureToggle(name: "Toggleable", remoteValue: false)

        toggle.localValue = true
        XCTAssertTrue(toggle.localValue)

        toggle.localValue = false
        XCTAssertFalse(toggle.localValue)
    }

    // MARK: - Value (Computed) Tests

    func testValueReturnsLocalValueWhenNoABValue() {
        var toggle = FeatureToggle(name: "Simple Feature", remoteValue: false)
        toggle.localValue = true

        XCTAssertTrue(toggle.value)
    }

    func testValueDefaultsFalseWhenNotSet() {
        let toggle = FeatureToggle(name: "Unset Feature", remoteValue: true)
        // Without setting localValue, it defaults to false
        XCTAssertFalse(toggle.value)
    }

    // MARK: - UserDefaults Key Generation Tests

    func testDefaultsKeyGeneration() {
        // The key should be lowercase with underscores
        var toggle1 = FeatureToggle(name: "Feature One", remoteValue: false)
        toggle1.localValue = true

        // Different name should have different storage
        var toggle2 = FeatureToggle(name: "Feature Two", remoteValue: false)
        toggle2.localValue = false

        XCTAssertTrue(toggle1.localValue)
        XCTAssertFalse(toggle2.localValue)
    }

    func testDifferentNamesHaveDifferentStorage() {
        var toggleA = FeatureToggle(name: "Alpha", remoteValue: false)
        var toggleB = FeatureToggle(name: "Beta", remoteValue: false)

        toggleA.localValue = true
        toggleB.localValue = false

        XCTAssertTrue(toggleA.localValue)
        XCTAssertFalse(toggleB.localValue)
    }

    // MARK: - Real-World Scenario Tests

    func testFeatureFlagWorkflow() {
        // Simulate a feature flag workflow
        var darkModeToggle = FeatureToggle(name: "Dark Mode", remoteValue: false)

        // Initially disabled
        XCTAssertFalse(darkModeToggle.value)

        // User enables locally
        darkModeToggle.localValue = true
        XCTAssertTrue(darkModeToggle.value)

        // User disables locally
        darkModeToggle.localValue = false
        XCTAssertFalse(darkModeToggle.value)
    }

    func testMultipleFeatureFlags() {
        var feature1 = FeatureToggle(name: "Feature 1", remoteValue: false)
        var feature2 = FeatureToggle(name: "Feature 2", remoteValue: true)
        var feature3 = FeatureToggle(name: "Feature 3", remoteValue: false)

        feature1.localValue = true
        feature3.localValue = true

        XCTAssertTrue(feature1.value)
        XCTAssertFalse(feature2.value)  // Not set locally, defaults to false
        XCTAssertTrue(feature3.value)
    }
}
#endif
