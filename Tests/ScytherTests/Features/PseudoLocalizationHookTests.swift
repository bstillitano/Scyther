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

    override func tearDown() {
        PseudoLocalizationHostHook.shared.setEnabled(false)
        PseudoLocalization.instance.reset()
        super.tearDown()
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
        PseudoLocalizationHostHook.shared.setEnabled(true)
        XCTAssertTrue(PseudoLocalizationHostHook.shared.isInstalled)
    }

    func testInstallingTwiceDoesNotUninstall() {
        PseudoLocalization.instance.accented = true
        PseudoLocalizationHostHook.shared.setEnabled(true)
        PseudoLocalizationHostHook.shared.setEnabled(true)

        XCTAssertTrue(PseudoLocalizationHostHook.shared.isInstalled)
        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ŠçýţĥéŕĤööķÞŕöƀé")
    }

    func testTheHookTransformsStringsLoadedFromTheMainBundle() {
        PseudoLocalization.instance.accented = true
        PseudoLocalizationHostHook.shared.setEnabled(true)

        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ŠçýţĥéŕĤööķÞŕöƀé")
    }

    func testTheHookReachesNSLocalizedString() {
        PseudoLocalization.instance.accented = true
        PseudoLocalizationHostHook.shared.setEnabled(true)

        XCTAssertEqual(NSLocalizedString("ScytherHookProbe", comment: ""), "ŠçýţĥéŕĤööķÞŕöƀé")
    }

    func testTheHookLeavesBundlesOtherThanTheMainBundleAlone() {
        PseudoLocalization.instance.accented = true
        PseudoLocalizationHostHook.shared.setEnabled(true)

        let other = ScytherLocalization.moduleBundle.localizedString(
            forKey: "ScytherHookProbe", value: nil, table: nil
        )
        XCTAssertEqual(other, "ScytherHookProbe")
    }

    func testTheHookDoesNothingWhileEveryModeIsOff() {
        PseudoLocalizationHostHook.shared.setEnabled(true)
        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ScytherHookProbe")
    }

    func testRemovingTheHookRestoresTheOriginalLookup() {
        PseudoLocalization.instance.accented = true
        PseudoLocalizationHostHook.shared.setEnabled(true)
        PseudoLocalizationHostHook.shared.setEnabled(false)

        XCTAssertFalse(PseudoLocalizationHostHook.shared.isInstalled)
        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ScytherHookProbe")
    }

    func testRemovingTheHookTwiceIsHarmless() {
        PseudoLocalization.instance.accented = true
        PseudoLocalizationHostHook.shared.setEnabled(true)
        PseudoLocalizationHostHook.shared.setEnabled(false)
        PseudoLocalizationHostHook.shared.setEnabled(false)

        XCTAssertEqual(mainBundleString(for: "ScytherHookProbe"), "ScytherHookProbe")
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
