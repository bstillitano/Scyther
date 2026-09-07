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

    func testNoModesAreStoredByDefault() {
        XCTAssertTrue(settings.storedModes.isEmpty)
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

    func testASecondInstanceReadsWhatTheFirstWrote() {
        settings.accented = true
        XCTAssertTrue(PseudoLocalization(defaults: defaults).accented)
    }

    // MARK: - Stored modes

    func testStoredModesReflectsEachSwitchIndependently() {
        settings.accented = true
        XCTAssertEqual(settings.storedModes, .accented)
        settings.showsKeys = true
        XCTAssertEqual(settings.storedModes, [.accented, .showsKeys])
        settings.lengthened = true
        settings.rightToLeft = true
        XCTAssertEqual(settings.storedModes, [.accented, .showsKeys, .lengthened, .rightToLeft])
    }

    // MARK: - Reset

    func testResetSwitchesEveryModeOff() {
        settings.accented = true
        settings.lengthened = true
        settings.rightToLeft = true
        settings.showsKeys = true

        settings.reset()

        XCTAssertTrue(settings.storedModes.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_accented"))
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_lengthened"))
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_right_to_left"))
        XCTAssertFalse(defaults.bool(forKey: "Scyther_pseudo_localization_show_keys"))
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

    // MARK: - Layout

    func testForcingRightToLeftMirrorsAnEnglishInterface() {
        XCTAssertEqual(
            PseudoLocalizationLayout.layoutDirection(forcingRightToLeft: true, languageIdentifier: "en"),
            .rightToLeft
        )
    }

    func testAnEnglishInterfaceStaysLeftToRightWithTheModeOff() {
        XCTAssertEqual(
            PseudoLocalizationLayout.layoutDirection(forcingRightToLeft: false, languageIdentifier: "en"),
            .leftToRight
        )
    }

    func testAnArabicInterfaceIsStillRightToLeftWithTheModeOff() {
        XCTAssertEqual(
            PseudoLocalizationLayout.layoutDirection(forcingRightToLeft: false, languageIdentifier: "ar"),
            .rightToLeft
        )
    }

    func testForcingRightToLeftDoesNotFightAnArabicInterface() {
        XCTAssertEqual(
            PseudoLocalizationLayout.layoutDirection(forcingRightToLeft: true, languageIdentifier: "ar"),
            .rightToLeft
        )
    }

    func testApplyingEffectsAnnouncesTheChangeSoViewsAlreadyOnScreenCanReRender() {
        let announced = expectation(
            forNotification: PseudoLocalization.ModesChangedNotification,
            object: nil,
            handler: nil
        )
        settings.rightToLeft = true
        settings.applyEffects(isTestCase: true, isAppStore: true)

        wait(for: [announced], timeout: 1)
    }

    func testForcingRightToLeftAsksForTheForcedAttribute() {
        XCTAssertEqual(PseudoLocalizationLayout.attribute(rightToLeft: true), .forceRightToLeft)
    }

    func testNotForcingRightToLeftLeavesTheDirectionUnspecifiedRatherThanPinnedLeftToRight() {
        XCTAssertEqual(PseudoLocalizationLayout.attribute(rightToLeft: false), .unspecified)
    }
}
#endif
