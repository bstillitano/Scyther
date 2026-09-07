//
//  PseudoLocalizationTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
@testable import Scyther
import SwiftUI
import XCTest

@MainActor
final class PseudoLocalizationTests: XCTestCase {

    /// A throwaway suite, so nothing here touches the settings a developer has persisted.
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var settings: PseudoLocalization!

    override func setUp() {
        super.setUp()
        suiteName = "PseudoLocalizationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = PseudoLocalization(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        settings = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testEveryModeIsOffByDefault() {
        XCTAssertFalse(settings.accented)
        XCTAssertFalse(settings.lengthened)
        XCTAssertFalse(settings.rightToLeft)
        XCTAssertFalse(settings.showsKeys)
    }

    func testNoTextModeIsStoredByDefault() {
        XCTAssertTrue(settings.storedModes.intersection(.textAffecting).isEmpty)
        XCTAssertFalse(settings.storedModes.contains(.rightToLeft))
    }

    /// The one switch that is on with nothing stored, so an install that predates it keeps the
    /// brackets it has always had.
    func testShowingBoundariesIsOnByDefault() {
        XCTAssertTrue(settings.showsBoundaries)
        XCTAssertNil(defaults.object(forKey: "Scyther_pseudo_localization_show_boundaries"))
        XCTAssertEqual(settings.storedModes, .showsBoundaries)
    }

    func testShowingBoundariesCanBeSwitchedOff() {
        settings.showsBoundaries = false
        XCTAssertFalse(settings.showsBoundaries)
        XCTAssertFalse(settings.storedModes.contains(.showsBoundaries))
    }

    // MARK: - Persistence

    func testAccentedPersistsUnderItsNamespacedKey() {
        settings.accented = true
        XCTAssertTrue(defaults.bool(forKey: "Scyther_pseudo_localization_accented"))
        XCTAssertTrue(settings.accented)
    }

    func testLengthenedPersistsUnderItsNamespacedKey() {
        settings.lengthened = true
        XCTAssertTrue(defaults.bool(forKey: "Scyther_pseudo_localization_lengthened"))
        XCTAssertTrue(settings.lengthened)
    }

    func testRightToLeftPersistsUnderItsNamespacedKey() {
        settings.rightToLeft = true
        XCTAssertTrue(defaults.bool(forKey: "Scyther_pseudo_localization_right_to_left"))
        XCTAssertTrue(settings.rightToLeft)
    }

    func testShowsKeysPersistsUnderItsNamespacedKey() {
        settings.showsKeys = true
        XCTAssertTrue(defaults.bool(forKey: "Scyther_pseudo_localization_show_keys"))
        XCTAssertTrue(settings.showsKeys)
    }

    func testShowsBoundariesPersistsUnderItsNamespacedKey() {
        settings.showsBoundaries = false
        XCTAssertEqual(defaults.object(forKey: "Scyther_pseudo_localization_show_boundaries") as? Bool, false)
        XCTAssertFalse(settings.showsBoundaries)
        settings.showsBoundaries = true
        XCTAssertEqual(defaults.object(forKey: "Scyther_pseudo_localization_show_boundaries") as? Bool, true)
        XCTAssertTrue(settings.showsBoundaries)
    }

    func testASecondInstanceReadsWhatTheFirstWrote() {
        settings.accented = true
        XCTAssertTrue(PseudoLocalization(defaults: defaults).accented)
    }

    // MARK: - Stored modes

    func testStoredModesReflectsEachSwitchIndependently() {
        settings.showsBoundaries = false
        settings.accented = true
        XCTAssertEqual(settings.storedModes, .accented)
        settings.showsKeys = true
        XCTAssertEqual(settings.storedModes, [.accented, .showsKeys])
        settings.lengthened = true
        settings.rightToLeft = true
        XCTAssertEqual(settings.storedModes, [.accented, .showsKeys, .lengthened, .rightToLeft])
        settings.showsBoundaries = true
        XCTAssertEqual(
            settings.storedModes,
            [.accented, .showsKeys, .lengthened, .rightToLeft, .showsBoundaries]
        )
    }

    // MARK: - Reset

    func testResetSwitchesEveryModeOff() {
        settings.accented = true
        settings.lengthened = true
        settings.rightToLeft = true
        settings.showsKeys = true

        settings.reset()

        XCTAssertEqual(settings.storedModes, .showsBoundaries)
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_accented"))
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_lengthened"))
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_right_to_left"))
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_show_keys"))
    }

    /// Reset restores the shipped state rather than clearing every switch, and for the brackets
    /// the shipped state is on.
    func testResetPutsTheBoundariesBackOn() {
        settings.showsBoundaries = false
        settings.reset()
        XCTAssertTrue(settings.showsBoundaries)
    }

    // MARK: - Production guard

    func testAnAppStoreBuildHonoursNoStoredMode() {
        XCTAssertEqual(
            PseudoLocalization.resolvedModes(stored: [.accented, .rightToLeft], isAppStore: true),
            []
        )
    }

    func testANonAppStoreBuildHonoursEveryStoredMode() {
        XCTAssertEqual(
            PseudoLocalization.resolvedModes(stored: [.accented, .rightToLeft], isAppStore: false),
            [.accented, .rightToLeft]
        )
    }

    // MARK: - Host guard

    func testTheHostAppIsTouchedOnlyOutsideTestsAndOutsideTheAppStore() {
        XCTAssertTrue(PseudoLocalization.canAffectHostApp(isTestCase: false, isAppStore: false))
        XCTAssertFalse(PseudoLocalization.canAffectHostApp(isTestCase: true, isAppStore: false))
        XCTAssertFalse(PseudoLocalization.canAffectHostApp(isTestCase: false, isAppStore: true))
        XCTAssertFalse(PseudoLocalization.canAffectHostApp(isTestCase: true, isAppStore: true))
    }
}
#endif
