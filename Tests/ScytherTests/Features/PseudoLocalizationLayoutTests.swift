//
//  PseudoLocalizationLayoutTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

/// Covers the half of ``PseudoLocalizationLayout`` that reaches the host app.
///
/// Testable in a way its predecessor never was, and that is the point of the mechanism as much as
/// its reach: forcing a layout direction meant writing an attribute onto live views, which a test
/// could only inspect and never judge — three fixes passed every assertion while the menu was
/// unreadable on a device. Writing two defaults keys is a fact a throwaway suite can hold, so what
/// the tests below assert and what the developer's app will do at launch are the same statement.
///
/// The suite is a throwaway one on purpose. The production path writes to `UserDefaults.standard`,
/// which in this process is the *test host's* domain, and a test that mirrored the test runner
/// would be a memorable way to find out that the guard works.
@MainActor
final class PseudoLocalizationLayoutTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    private let textDirection = PseudoLocalizationLayout.textDirectionDefaultsKey
    private let forceRightToLeft = PseudoLocalizationLayout.forceRightToLeftDefaultsKey

    override func setUp() {
        super.setUp()
        suiteName = "PseudoLocalizationLayoutTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Puts the keys in the state a session that switched the mode on would have left them.
    private func stubSwitchedOn() {
        defaults.set(true, forKey: textDirection)
        defaults.set(true, forKey: forceRightToLeft)
    }

    /// Runs the host-app half as a build where Scyther is allowed to run would.
    private func apply(rightToLeft: Bool, isTestCase: Bool = false, isAppStore: Bool = false) {
        PseudoLocalizationLayout.applyToHostApp(
            rightToLeft: rightToLeft,
            isTestCase: isTestCase,
            isAppStore: isAppStore,
            systemDefaults: defaults
        )
    }

    // MARK: - Switching on

    func testSwitchingOnWritesBothKeysIOSReadsAtLaunch() {
        apply(rightToLeft: true)
        XCTAssertEqual(defaults.object(forKey: textDirection) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: forceRightToLeft) as? Bool, true)
    }

    /// The keys are the ones Xcode's own Right to Left Pseudolanguage scheme option passes, which
    /// is what makes this reach SwiftUI as well as UIKit. Getting a name wrong would fail silently
    /// on a device and look exactly like the feature not working.
    func testTheKeysAreTheOnesTheSystemReads() {
        XCTAssertEqual(PseudoLocalizationLayout.textDirectionDefaultsKey, "AppleTextDirection")
        XCTAssertEqual(
            PseudoLocalizationLayout.forceRightToLeftDefaultsKey,
            "NSForceRightToLeftWritingDirection"
        )
    }

    // MARK: - Switching off

    /// Removed rather than set to `false`: a developer who tries this once has to be able to get
    /// their app back, without a Scyther-shaped value left in their defaults for good.
    func testSwitchingOffRemovesBothKeysRatherThanWritingFalse() {
        stubSwitchedOn()
        apply(rightToLeft: false)
        XCTAssertNil(defaults.object(forKey: textDirection))
        XCTAssertNil(defaults.object(forKey: forceRightToLeft))
    }

    func testSwitchingOffWithNothingStoredLeavesNothingBehind() {
        apply(rightToLeft: false)
        XCTAssertNil(defaults.object(forKey: textDirection))
        XCTAssertNil(defaults.object(forKey: forceRightToLeft))
    }

    func testOnThenOffLeavesTheDefaultsAsTheyWereFound() {
        apply(rightToLeft: true)
        apply(rightToLeft: false)
        XCTAssertNil(defaults.object(forKey: textDirection))
        XCTAssertNil(defaults.object(forKey: forceRightToLeft))
    }

    // MARK: - The guard

    func testNothingIsWrittenUnderXCTest() {
        apply(rightToLeft: true, isTestCase: true)
        XCTAssertNil(defaults.object(forKey: textDirection))
        XCTAssertNil(defaults.object(forKey: forceRightToLeft))
    }

    /// Under XCTest the off path must not write *or* remove: the standard domain in this process
    /// belongs to the test host, and a test suite has no business editing it in either direction.
    func testNothingIsRemovedUnderXCTest() {
        stubSwitchedOn()
        apply(rightToLeft: false, isTestCase: true)
        XCTAssertEqual(defaults.object(forKey: textDirection) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: forceRightToLeft) as? Bool, true)
    }

    func testAnAppStoreBuildNeverMirrorsTheHostApp() {
        apply(rightToLeft: true, isAppStore: true)
        XCTAssertNil(defaults.object(forKey: textDirection))
        XCTAssertNil(defaults.object(forKey: forceRightToLeft))
    }

    /// The asymmetry is the safe direction to err in: a switch left on in a TestFlight build and
    /// carried into a store build through the same preferences file must be cleared, not preserved.
    func testAnAppStoreBuildStillClearsAStaleKey() {
        stubSwitchedOn()
        apply(rightToLeft: false, isAppStore: true)
        XCTAssertNil(defaults.object(forKey: textDirection))
        XCTAssertNil(defaults.object(forKey: forceRightToLeft))
    }
}
#endif
