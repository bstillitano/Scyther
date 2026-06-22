//
//  FeatureFlagsTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 22/6/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class FeatureFlagsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        cleanupUserDefaults()
    }

    override func tearDown() {
        cleanupUserDefaults()
        super.tearDown()
    }

    private func cleanupUserDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("Scyther_toggler_local_value_") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: FeatureFlags.overridesEnabledKey)
    }

    // MARK: - Key Consistency Tests

    func testOverridesEnabledKeyMatchesLegacyValue() {
        XCTAssertEqual(FeatureFlags.overridesEnabledKey, "scyther.featureFlags.overridesEnabled")
    }

    func testLocalValueKeyMatchesLegacyDerivation() {
        XCTAssertEqual(FeatureToggle.localValueKey(for: "My Flag"), "Scyther_toggler_local_value_my_flag")
        XCTAssertEqual(FeatureToggle.localValueKey(for: "Secret Feature"), "Scyther_toggler_local_value_secret_feature")
    }

    // MARK: - localOverride(for:) Tests

    func testLocalOverrideReturnsNilWhenOverridesDisabled() {
        // A local value is stored, but overrides are globally off.
        UserDefaults.standard.set(false, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.standard.set(true, forKey: FeatureToggle.localValueKey(for: "Flag A"))

        XCTAssertNil(FeatureFlags.shared.localOverride(for: "Flag A"))
    }

    func testLocalOverrideReturnsNilWhenFlagNeverOverridden() {
        // Overrides on, but this flag has no stored value.
        UserDefaults.standard.set(true, forKey: FeatureFlags.overridesEnabledKey)

        XCTAssertNil(FeatureFlags.shared.localOverride(for: "Never Set"))
    }

    func testLocalOverrideReturnsTrueWhenSet() {
        UserDefaults.standard.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.standard.set(true, forKey: FeatureToggle.localValueKey(for: "Flag B"))

        XCTAssertEqual(FeatureFlags.shared.localOverride(for: "Flag B"), true)
    }

    func testLocalOverrideReturnsFalseWhenSet() {
        UserDefaults.standard.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.standard.set(false, forKey: FeatureToggle.localValueKey(for: "Flag C"))

        XCTAssertEqual(FeatureFlags.shared.localOverride(for: "Flag C"), false)
    }

    func testLocalOverrideRoundTripsThroughToggleKeyDerivation() {
        // Writing under the derived key for a spaced name must be readable via the accessor.
        UserDefaults.standard.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.standard.set(true, forKey: FeatureToggle.localValueKey(for: "New Dashboard"))

        XCTAssertEqual(FeatureFlags.shared.localOverride(for: "New Dashboard"), true)
    }

    func testFacadeAndOverrideReadableFromDetachedTask() async {
        // Proves the whole path is usable off the main actor with no main-actor hop:
        // the `Scyther.featureFlags` facade is reachable from a detached (non-main) task and
        // `localOverride(for:)` reads correctly there.
        UserDefaults.standard.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.standard.set(true, forKey: FeatureToggle.localValueKey(for: "Off Main"))

        let value = await Task.detached { Scyther.featureFlags.localOverride(for: "Off Main") }.value

        XCTAssertEqual(value, true)
    }
}
#endif
