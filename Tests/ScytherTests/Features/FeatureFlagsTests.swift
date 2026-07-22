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
        let defaults = UserDefaults.scyther
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
        UserDefaults.scyther.set(false, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.scyther.set(true, forKey: FeatureToggle.localValueKey(for: "Flag A"))

        XCTAssertNil(FeatureFlags.shared.localOverride(for: "Flag A"))
    }

    func testLocalOverrideReturnsNilWhenFlagNeverOverridden() {
        // Overrides on, but this flag has no stored value.
        UserDefaults.scyther.set(true, forKey: FeatureFlags.overridesEnabledKey)

        XCTAssertNil(FeatureFlags.shared.localOverride(for: "Never Set"))
    }

    func testLocalOverrideReturnsTrueWhenSet() {
        UserDefaults.scyther.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.scyther.set(true, forKey: FeatureToggle.localValueKey(for: "Flag B"))

        XCTAssertEqual(FeatureFlags.shared.localOverride(for: "Flag B"), true)
    }

    func testLocalOverrideReturnsFalseWhenSet() {
        UserDefaults.scyther.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.scyther.set(false, forKey: FeatureToggle.localValueKey(for: "Flag C"))

        XCTAssertEqual(FeatureFlags.shared.localOverride(for: "Flag C"), false)
    }

    func testLocalOverrideRoundTripsThroughToggleKeyDerivation() {
        // Writing under the derived key for a spaced name must be readable via the accessor.
        UserDefaults.scyther.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.scyther.set(true, forKey: FeatureToggle.localValueKey(for: "New Dashboard"))

        XCTAssertEqual(FeatureFlags.shared.localOverride(for: "New Dashboard"), true)
    }

    // MARK: - clearLocalValue(for:) Tests

    @MainActor
    func testClearLocalValueRevertsToRemote() {
        UserDefaults.scyther.set(true, forKey: FeatureFlags.overridesEnabledKey)
        let flags = FeatureFlags.shared
        flags.register("Clearable Flag", remoteValue: true)
        flags.setLocalValue(false, for: "Clearable Flag")
        XCTAssertEqual(flags.localOverride(for: "Clearable Flag"), false)

        flags.clearLocalValue(for: "Clearable Flag")

        // Override gone, so isEnabled falls back to the remote value.
        XCTAssertNil(flags.localOverride(for: "Clearable Flag"))
        XCTAssertTrue(flags.isEnabled("Clearable Flag"))
    }

    @MainActor
    func testClearLocalValueIsNoOpForUnknownFlag() {
        // Should not crash or affect other flags.
        FeatureFlags.shared.clearLocalValue(for: "Does Not Exist")
        XCTAssertNil(FeatureFlags.shared.localOverride(for: "Does Not Exist"))
    }

    // MARK: - clearAllLocalValues() Tests

    @MainActor
    func testClearAllLocalValuesClearsEveryFlag() {
        UserDefaults.scyther.set(true, forKey: FeatureFlags.overridesEnabledKey)
        let flags = FeatureFlags.shared
        flags.register("Flag One", remoteValue: false)
        flags.register("Flag Two", remoteValue: true)
        flags.setLocalValue(true, for: "Flag One")
        flags.setLocalValue(false, for: "Flag Two")

        flags.clearAllLocalValues()

        XCTAssertNil(flags.localOverride(for: "Flag One"))
        XCTAssertNil(flags.localOverride(for: "Flag Two"))
    }

    // MARK: - localValue(for:) Tests

    @MainActor
    func testLocalValueForReturnsNilWhenNoOverride() {
        let flags = FeatureFlags.shared
        flags.register("Unset Local", remoteValue: true)
        XCTAssertNil(flags.localValue(for: "Unset Local"))
    }

    @MainActor
    func testLocalValueForReturnsStoredOverride() {
        let flags = FeatureFlags.shared
        flags.register("Set Local", remoteValue: true)
        flags.setLocalValue(false, for: "Set Local")
        XCTAssertEqual(flags.localValue(for: "Set Local"), false)
    }

    func testFacadeAndOverrideReadableFromDetachedTask() async {
        // Proves the whole path is usable off the main actor with no main-actor hop:
        // the `Scyther.featureFlags` facade is reachable from a detached (non-main) task and
        // `localOverride(for:)` reads correctly there.
        UserDefaults.scyther.set(true, forKey: FeatureFlags.overridesEnabledKey)
        UserDefaults.scyther.set(true, forKey: FeatureToggle.localValueKey(for: "Off Main"))

        let value = await Task.detached { Scyther.featureFlags.localOverride(for: "Off Main") }.value

        XCTAssertEqual(value, true)
    }

    // MARK: - Pinned toggles stay in the full list

    /// Flags register into the shared `Scyther.featureFlags` singleton and there is no
    /// public API to unregister them, so these tests use distinctive names and assert by
    /// containment rather than whole-array equality. Another test registering its own flags
    /// must not be able to break them.
    @MainActor
    private func makeSuite(named suiteName: String) -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return UserDefaults(suiteName: suiteName)!
    }

    @MainActor
    func testPinnedTogglesRemainInTheFullToggleList() async {
        let defaults = makeSuite(named: "com.scyther.tests.featureflags")
        Scyther.featureFlags.register("ScytherTestPinned", remoteValue: true)

        let viewModel = FeatureFlagsViewModel(defaults: defaults)
        await viewModel.onFirstAppear()
        viewModel.togglePin(for: "ScytherTestPinned")

        XCTAssertTrue(
            viewModel.pinnedToggles.contains { $0.name == "ScytherTestPinned" },
            "Pinned toggle is missing from the Pinned section"
        )
        XCTAssertTrue(
            viewModel.toggles.contains { $0.name == "ScytherTestPinned" && $0.isPinned },
            "Pinned toggle must remain in the full list, flagged as pinned"
        )
    }

    @MainActor
    func testPinnedTogglesAreOrderedAlphabeticallyNotByPinOrder() async {
        let defaults = makeSuite(named: "com.scyther.tests.featureflags.order")
        Scyther.featureFlags.register("ScytherTestOrderZulu", remoteValue: true)
        Scyther.featureFlags.register("ScytherTestOrderAlpha", remoteValue: true)

        let viewModel = FeatureFlagsViewModel(defaults: defaults)
        await viewModel.onFirstAppear()

        // Pin Zulu first. Alphabetical ordering must still put Alpha ahead of it.
        viewModel.togglePin(for: "ScytherTestOrderZulu")
        viewModel.togglePin(for: "ScytherTestOrderAlpha")

        let names = viewModel.pinnedToggles.map(\.name).filter { $0.hasPrefix("ScytherTestOrder") }
        XCTAssertEqual(names, ["ScytherTestOrderAlpha", "ScytherTestOrderZulu"])
    }

    @MainActor
    func testUnpinningLeavesTheToggleInTheFullList() async {
        let defaults = makeSuite(named: "com.scyther.tests.featureflags.unpin")
        Scyther.featureFlags.register("ScytherTestUnpin", remoteValue: false)

        let viewModel = FeatureFlagsViewModel(defaults: defaults)
        await viewModel.onFirstAppear()
        viewModel.togglePin(for: "ScytherTestUnpin")
        viewModel.togglePin(for: "ScytherTestUnpin")

        XCTAssertFalse(viewModel.pinnedToggles.contains { $0.name == "ScytherTestUnpin" })
        XCTAssertTrue(viewModel.toggles.contains { $0.name == "ScytherTestUnpin" })
    }

    @MainActor
    func testOverridesEnabledPropagatesToTheFeatureFlagsSubsystem() {
        let viewModel = FeatureFlagsViewModel()

        viewModel.overridesEnabled = true
        XCTAssertTrue(Scyther.featureFlags.localOverridesEnabled)

        viewModel.overridesEnabled = false
        XCTAssertFalse(Scyther.featureFlags.localOverridesEnabled)
    }
}
#endif
