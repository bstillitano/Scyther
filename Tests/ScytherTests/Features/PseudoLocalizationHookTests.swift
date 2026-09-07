//
//  PseudoLocalizationHookTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

/// Exercises the two places pseudo-localisation actually hooks in: Scyther's own
/// ``localized(_:comment:override:)``, and the swizzle on `Bundle.localizedString(forKey:value:table:)`.
///
/// Both write to the shared singleton, and therefore to Scyther's real defaults suite, because
/// both are read from `PseudoLocalization.instance` on paths that take no injected store —
/// `localized(_:)` is a free function called from every corner of the package, and the swizzled
/// `NSBundle` method is reached by the Objective-C runtime with no seam to pass anything through.
/// Every test here therefore resets the singleton in `tearDown`.
@MainActor
final class PseudoLocalizationHookTests: XCTestCase {

    /// The developer's own switches, captured so the suite can put them back.
    ///
    /// An earlier version simply called `reset()` in `tearDown`, which meant running the test
    /// suite silently switched off any pseudo-localisation the developer had left on. The shared
    /// singleton cannot be pointed at a throwaway suite from here — `localized(_:)` is a free
    /// function that reaches `PseudoLocalization.instance` with no seam to pass one through — so
    /// the next best thing is to leave the suite exactly as it was found.
    private var restore: [String: Bool] = [:]

    override func setUp() {
        super.setUp()
        restore = [
            PseudoLocalization.AccentedDefaultsKey: PseudoLocalization.instance.accented,
            PseudoLocalization.LengthenedDefaultsKey: PseudoLocalization.instance.lengthened,
            PseudoLocalization.RightToLeftDefaultsKey: PseudoLocalization.instance.rightToLeft,
            PseudoLocalization.ShowsKeysDefaultsKey: PseudoLocalization.instance.showsKeys,
            PseudoLocalization.ShowsBoundariesDefaultsKey: PseudoLocalization.instance.showsBoundaries,
        ]
    }

    override func tearDown() {
        PseudoLocalizationHostHook.shared.setEnabled(false)
        for (key, value) in restore {
            UserDefaults.scyther.setValue(value, forKey: key)
        }
        super.tearDown()
    }

    /// Installs the swizzle the way a real, non-test build would.
    ///
    /// ``PseudoLocalizationHostHook/setEnabled(_:isTestCase:isAppStore:)`` refuses to install
    /// under XCTest, which is the point of it — so the tests that exercise the swizzle for real
    /// have to say explicitly that they are standing in for a build where it is allowed.
    private func installHook() {
        PseudoLocalizationHostHook.shared.setEnabled(true, isTestCase: false, isAppStore: false)
    }

    // MARK: - Scyther's own strings

    func testAccentingReachesScythersOwnStrings() {
        let before = localized("Grid Overlay")
        PseudoLocalization.instance.accented = true
        let after = localized("Grid Overlay")

        XCTAssertNotEqual(after, before)
        XCTAssertFalse(after.contains(where: { $0.isASCII && $0.isLetter }), "\(after) is still plain ASCII")
    }

    func testLengtheningReachesScythersOwnStrings() {
        PseudoLocalization.instance.lengthened = true
        let after = localized("Grid Overlay")

        XCTAssertTrue(after.hasPrefix("["), "\(after) is not bracketed")
        XCTAssertTrue(after.hasSuffix("]"), "\(after) is not bracketed")
    }

    func testShowingKeysRendersTheCatalogKeyIncludingItsSpecifiers() {
        PseudoLocalization.instance.showsKeys = true
        let count = 5
        XCTAssertEqual(localized("Selected \(count) items"), "Selected %lld items")
    }

    func testEveryModeOffLeavesScythersOwnStringsExactlyAsResolved() {
        XCTAssertEqual(localized("Grid Overlay"), localizedChrome("Grid Overlay"))
    }

    func testRightToLeftAloneChangesNoScytherString() {
        let before = localized("Grid Overlay")
        PseudoLocalization.instance.rightToLeft = true
        XCTAssertEqual(localized("Grid Overlay"), before)
    }

    // MARK: - The escape hatch

    func testTheChromePathIsNeverTransformed() {
        let before = localizedChrome("Turn Everything Off")
        PseudoLocalization.instance.accented = true
        PseudoLocalization.instance.lengthened = true

        XCTAssertEqual(localizedChrome("Turn Everything Off"), before)
        XCTAssertNotEqual(localized("Turn Everything Off"), before,
                          "the modes were not actually in force, so the exemption proved nothing")
    }

    func testThePseudoLocalisationMenuRowStaysReadableWhileEveryOtherRowDoesNot() {
        let escapeHatch = MenuItem.pseudoLocalization.title
        let ordinaryRow = MenuItem.gridOverlay.title
        PseudoLocalization.instance.accented = true

        XCTAssertEqual(MenuItem.pseudoLocalization.title, escapeHatch)
        XCTAssertNotEqual(MenuItem.gridOverlay.title, ordinaryRow)
    }

    // MARK: - The host-app hook

    func testTheHookIsNotInstalledUntilItIsAskedFor() {
        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testInstallingTheHookIsRecorded() {
        installHook()
        XCTAssertTrue(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testInstallingTwiceDoesNotUninstall() {
        PseudoLocalization.instance.accented = true
        installHook()
        installHook()

        XCTAssertTrue(PseudoLocalizationHostHook.shared.isInstalled)
        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ŠçýţĥéŕĤööķÞŕöƀé")
    }

    func testTheHookTransformsStringsLoadedFromTheMainBundle() {
        PseudoLocalization.instance.accented = true
        installHook()

        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ŠçýţĥéŕĤööķÞŕöƀé")
    }

    func testTheHookReachesNSLocalizedString() {
        PseudoLocalization.instance.accented = true
        installHook()

        XCTAssertEqual(NSLocalizedString("ScytherHookProbe", comment: ""), "ŠçýţĥéŕĤööķÞŕöƀé")
    }

    func testTheHookLeavesBundlesOtherThanTheMainBundleAlone() {
        PseudoLocalization.instance.accented = true
        installHook()

        let other = ScytherLocalization.moduleBundle.localizedString(
            forKey: "ScytherHookProbe", value: nil, table: nil
        )
        XCTAssertEqual(other, "ScytherHookProbe")
    }

    func testTheHookDoesNothingWhileEveryModeIsOff() {
        installHook()
        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ScytherHookProbe")
    }

    func testRemovingTheHookRestoresTheOriginalLookup() {
        PseudoLocalization.instance.accented = true
        installHook()
        PseudoLocalizationHostHook.shared.setEnabled(false)

        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ScytherHookProbe")
    }

    func testRemovingTheHookTwiceIsHarmless() {
        PseudoLocalization.instance.accented = true
        installHook()
        PseudoLocalizationHostHook.shared.setEnabled(false)
        PseudoLocalizationHostHook.shared.setEnabled(false)

        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ScytherHookProbe")
    }

    // MARK: - The host-app hook: scope and guards

    func testTheHookRefusesToInstallItselfUnderXCTest() {
        PseudoLocalizationHostHook.shared.setEnabled(true)
        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testTheHookRefusesToInstallItselfOnAnAppStoreBuild() {
        PseudoLocalizationHostHook.shared.setEnabled(true, isTestCase: false, isAppStore: true)
        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testRemovingTheHookIsNeverRefused() {
        installHook()
        PseudoLocalizationHostHook.shared.setEnabled(false, isTestCase: true, isAppStore: true)
        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testOnlyTheDefaultTableIsInScope() {
        XCTAssertTrue(PseudoLocalizationHostHook.transforms(table: nil))
        XCTAssertTrue(PseudoLocalizationHostHook.transforms(table: "Localizable"))
        XCTAssertFalse(PseudoLocalizationHostHook.transforms(table: "Analytics"))
    }

    func testTheHookLeavesANamedTableAlone() {
        PseudoLocalization.instance.accented = true
        installHook()

        let named = Bundle.main.localizedString(forKey: "ScytherHookProbe", value: nil, table: "Analytics")
        XCTAssertEqual(named, "ScytherHookProbe")
    }

    func testTheHookLeavesAPluralFormatAlone() {
        PseudoLocalization.instance.accented = true
        PseudoLocalization.instance.lengthened = true
        installHook()

        XCTAssertEqual(mainBundleString(for: "%#@count@ items"), "%#@count@ items")
    }

    /// Pins the limit the README's central claim rests on.
    ///
    /// `String(localized:)` is documented — in the README, in the DocC article and in this type's
    /// own header — as *not* reachable by the swizzle, which is what makes the honest claim
    /// "on a SwiftUI app this is a demonstration, not a test of your screens". That was measured
    /// once, in prose. If a future Foundation routes it back through `NSBundle`, this test goes
    /// red and the documentation has to be rewritten, rather than quietly becoming wrong.
    func testStringLocalizedStillDoesNotReachTheHook() {
        PseudoLocalization.instance.accented = true
        installHook()

        XCTAssertEqual(String(localized: "ScytherHookProbe", bundle: .main), "ScytherHookProbe")
    }

    // MARK: - Effects follow the settings

    func testEffectsInstallTheHookWhenATextModeIsOn() {
        PseudoLocalization.instance.accented = true
        PseudoLocalization.instance.applyEffects(isTestCase: false, isAppStore: false)

        XCTAssertTrue(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testEffectsLeaveTheHookOutForRightToLeftAlone() {
        PseudoLocalization.instance.rightToLeft = true
        PseudoLocalization.instance.applyEffects(isTestCase: false, isAppStore: false)

        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testResettingAndReapplyingTearsTheHookBackOut() {
        PseudoLocalization.instance.accented = true
        PseudoLocalization.instance.applyEffects(isTestCase: false, isAppStore: false)
        PseudoLocalization.instance.reset()
        PseudoLocalization.instance.applyEffects(isTestCase: false, isAppStore: false)

        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled,
                       "the feature could not be switched off")
    }

    func testEffectsFollowTheSettingsAtTheMomentTheyAreAppliedRatherThanWhenTheyWereRequested() {
        PseudoLocalization.instance.accented = true
        PseudoLocalization.instance.reset()
        PseudoLocalization.instance.applyEffects(isTestCase: false, isAppStore: false)

        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testEffectsInstallNothingUnderXCTest() {
        PseudoLocalization.instance.accented = true
        PseudoLocalization.instance.applyEffects()

        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
    }

    // MARK: - The settings page keeps its own copy readable

    func testTheSettingsPageSampleSourceIsNeverTransformed() {
        let viewModel = PseudoLocalizationViewModel()
        let before = viewModel.sampleSource
        PseudoLocalization.instance.accented = true
        PseudoLocalization.instance.lengthened = true

        XCTAssertEqual(viewModel.sampleSource, before)
    }

    func testTheSettingsPageSampleStillDemonstratesTheTransform() {
        let viewModel = PseudoLocalizationViewModel()
        viewModel.accented = true

        XCTAssertNotEqual(viewModel.sampleText, viewModel.sampleSource)
    }

    func testSearchingForPseudoStillFindsTheEscapeHatchWhileAccentedIsOn() {
        PseudoLocalization.instance.accented = true
        let targets = MenuSearchIndex.entries(matching: "pseudo", developerOptions: []).map(\.target)

        XCTAssertTrue(targets.contains(.pseudoLocalization),
                      "the search route back to the escape hatch is gone")
    }

    /// Looks a key up in `Bundle.main` the way `NSLocalizedString` does.
    ///
    /// The key is deliberately absent from every table, so Foundation's own answer is the key
    /// itself. That makes the assertion about the transform and nothing else: any difference from
    /// the key is the hook's doing.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: Whatever `Bundle.main` hands back.
    private func mainBundleString(for key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}
#endif
