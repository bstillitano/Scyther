//
//  InterfaceToolkitAccessibilityTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

@testable import Scyther
import UIKit
import XCTest

/// Covers the two decisions `InterfaceToolkit` makes on the live accessibility overlay's behalf:
/// *when* to re-audit, and *whether* a scheduled pass should run at all when it comes up.
///
/// Both are tested through injected seams rather than through a real window. `ScytherTests` has no
/// host app, so `AccessibilityAudit.auditKeyWindow()` refuses to walk anything and every window a
/// test can build is a fabrication — a test that went through the real path would pass whatever the
/// code did, which is the failure mode this suite exists to avoid.
@MainActor
final class InterfaceToolkitAccessibilityTests: XCTestCase {

    private let toolkit = InterfaceToolkit.instance
    nonisolated(unsafe) private var originalLiveEnabled = false
    nonisolated(unsafe) private var originalPass: (@MainActor () -> AccessibilityAuditor.Result)!
    nonisolated(unsafe) private var originalCoverage: (@MainActor () -> Bool)!
    nonisolated(unsafe) private var originalIdentity: (@MainActor () -> [ObjectIdentifier])!

    /// Puts the shared toolkit into a known state and remembers everything that has to go back.
    ///
    /// `InterfaceToolkit.instance` is a singleton and these tests write to it, so the teardown
    /// matters as much as the setup. Live mode is written straight to the defaults key rather than
    /// through `AccessibilityAudit.liveEnabled`, whose setter hops to the main actor to show or
    /// hide the overlay — a side effect this suite has no use for and would have to wait on.
    override func setUp() async throws {
        try await super.setUp()
        originalLiveEnabled = UserDefaults.scyther.bool(forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        originalPass = toolkit.runAccessibilityPass
        originalCoverage = toolkit.isScytherCoveringScreen
        originalIdentity = toolkit.accessibilityScreenIdentityProbe
        UserDefaults.scyther.setValue(true, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.isScytherCoveringScreen = { false }
        toolkit.accessibilityAuditView.findings = []
    }

    override func tearDown() async throws {
        toolkit.runAccessibilityPass = originalPass
        toolkit.isScytherCoveringScreen = originalCoverage
        toolkit.accessibilityScreenIdentityProbe = originalIdentity
        UserDefaults.scyther.setValue(originalLiveEnabled, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        // Cancels anything this test scheduled and empties the overlay, so no pending work item
        // fires into the next test.
        UserDefaults.scyther.setValue(false, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.showAccessibilityAudit()
        UserDefaults.scyther.setValue(originalLiveEnabled, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        try await super.tearDown()
    }

    /// One finding, so a pass can be told apart from no pass.
    private func result(_ name: String) -> AccessibilityAuditor.Result {
        AccessibilityAuditor.Result(
            findings: [AccessibilityFinding(check: .missingLabel,
                                            severity: .error,
                                            frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                                            elementName: name,
                                            detail: "detail")],
            didHitLimit: false,
            checksRun: Set(AccessibilityCheck.allCases)
        )
    }

    // MARK: - Following The App

    /// The defect: the boxes followed a rotation, a new `UIWindow` and the live-mode toggle, and
    /// nothing else. A push left them pinned to a screen that had gone, with a pill still offering
    /// a report about it.
    func testANavigationPushIsNoticedAsADifferentScreen() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let before = InterfaceToolkit.accessibilityScreenIdentity(from: navigation)

        navigation.pushViewController(UIViewController(), animated: false)

        XCTAssertNotEqual(InterfaceToolkit.accessibilityScreenIdentity(from: navigation), before)
    }

    /// A tab change replaces the whole screen and changes no frame the overlay owns.
    func testATabChangeIsNoticedAsADifferentScreen() {
        let tabs = UITabBarController()
        tabs.viewControllers = [UIViewController(), UIViewController()]
        let before = InterfaceToolkit.accessibilityScreenIdentity(from: tabs)

        tabs.selectedIndex = 1

        XCTAssertNotEqual(InterfaceToolkit.accessibilityScreenIdentity(from: tabs), before)
    }

    /// The app presenting one of its own screens is not Scyther covering the app — the boxes stay
    /// drawn, and they describe a screen the app's modal is now hiding.
    func testTheAppPresentingItsOwnScreenIsNoticed() {
        let root = PresentingController()
        let before = InterfaceToolkit.accessibilityScreenIdentity(from: root)

        // A real presentation needs a window, an anchor and an animation; what the walk reads is
        // `presentedViewController`, so that is what is stood in for.
        root.stubPresented = UIViewController()
        let after = InterfaceToolkit.accessibilityScreenIdentity(from: root)

        XCTAssertNotEqual(after, before)
        XCTAssertEqual(after.count, 2, "the chain should reach the controller actually showing")
    }

    /// The poll runs twice a second for as long as live mode is on, and a re-audit is a full tree
    /// walk plus a window snapshot — so only a *change* may schedule one. Arriving somewhere new
    /// must, and standing still must not.
    func testOnlyAChangeOfScreenSchedulesAReaudit() {
        let first = UIViewController()
        let second = UIViewController()
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.accessibilityScreenIdentityProbe = { [ObjectIdentifier(first)] }

        toolkit.pollAccessibilityScreen()
        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit, "arriving on a screen must re-audit")

        toolkit.runAccessibilityAudit()
        toolkit.pollAccessibilityScreen()
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit, "nothing moved, so nothing re-audits")

        toolkit.accessibilityScreenIdentityProbe = { [ObjectIdentifier(second)] }
        toolkit.pollAccessibilityScreen()

        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit,
                      "a push, a tab change or a modal must re-audit")
    }

    // MARK: - Deciding At The Moment The Pass Runs

    /// A pass is scheduled half a second before it runs, and Scyther's own report rises inside that
    /// gap. Such a pass walks a window that by then contains Scyther's report — which is how the
    /// report came to list Scyther's own Close and Re-run buttons as 36 × 36pt touch-target errors
    /// — measures the app through the sheet's transform, drops contrast because the pixels are
    /// Scyther's, and then overwrites the honest findings the pill counted with the poorer set.
    func testAPassIsAbandonedWhenScytherHasCoveredTheAppSinceItWasScheduled() {
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.runAccessibilityAudit()
        XCTAssertEqual(toolkit.accessibilityAuditView.findings.map(\.elementName), ["app"])

        toolkit.isScytherCoveringScreen = { true }
        toolkit.runAccessibilityPass = { self.result("through Scyther's own sheet") }
        toolkit.runAccessibilityAudit()

        XCTAssertEqual(toolkit.accessibilityAuditView.findings.map(\.elementName), ["app"],
                       "the honest pass must not be replaced by one taken through Scyther's own UI")
    }

    /// The pass that was abandoned is taken as soon as Scyther's screen goes away, which is also
    /// the only moment contrast can be measured against the app's own pixels again.
    func testTheAbandonedPassIsScheduledOnceScythersScreenGoesAway() {
        toolkit.isScytherCoveringScreen = { true }
        toolkit.runAccessibilityAudit()
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)

        toolkit.isScytherCoveringScreen = { false }
        toolkit.scytherCoverageDidChangeNotification(notification: NSNotification(name: .init("test"), object: nil))

        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit)
    }

    /// Nothing is scheduled while Scyther is still in front of the app: the notification fires for
    /// a screen appearing as well as for one going away.
    func testNothingIsScheduledWhenScytherHasJustCoveredTheApp() {
        toolkit.showAccessibilityAudit()
        toolkit.runAccessibilityAudit()
        toolkit.isScytherCoveringScreen = { true }

        toolkit.scytherCoverageDidChangeNotification(notification: NSNotification(name: .init("test"), object: nil))

        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
    }

    // MARK: - What The Report Opens Onto

    /// The pill's count and the report it opens have to describe the same pass. The report gets the
    /// last pass taken with nothing of Scyther's on screen — the one the pill counted.
    func testTheReportOpensOntoTheLastUncoveredPass() {
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.runAccessibilityAudit()

        toolkit.isScytherCoveringScreen = { true }

        XCTAssertEqual(toolkit.accessibilityResultForReport()?.findings.map(\.elementName), ["app"])
    }

    /// With nothing of Scyther's on screen there is no sheet to measure through, so the report has
    /// no reason to prefer an older pass to one of its own.
    func testTheReportTakesItsOwnPassWhenNothingIsCoveringTheApp() {
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.runAccessibilityAudit()

        XCTAssertNil(toolkit.accessibilityResultForReport())
    }
}

/// A controller that can be told it is presenting something.
///
/// A real presentation needs a window to anchor to and an animation to finish, neither of which
/// would make `presentedViewController` — the only thing the screen walk reads — any more true.
@MainActor
private final class PresentingController: UIViewController {
    /// What this controller reports as presented.
    var stubPresented: UIViewController?

    override var presentedViewController: UIViewController? { stubPresented }
}
