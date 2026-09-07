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
    nonisolated(unsafe) private var originalClock: (@MainActor () -> Date)!
    nonisolated(unsafe) private var originalCanAudit: (@MainActor () -> Bool)!

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
        originalClock = toolkit.accessibilityClock
        originalCanAudit = toolkit.canAuditThisBuild
        UserDefaults.scyther.setValue(true, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.isScytherCoveringScreen = { false }
        // `AppEnvironment.isTestCase` is unconditionally true here, so the real predicate would
        // refuse every pass and nothing below would ever be scheduled. Each test that is *about*
        // the refusal drives this seam itself.
        toolkit.canAuditThisBuild = { true }
        toolkit.accessibilityAuditView.findings = []
    }

    override func tearDown() async throws {
        toolkit.runAccessibilityPass = originalPass
        toolkit.isScytherCoveringScreen = originalCoverage
        toolkit.accessibilityScreenIdentityProbe = originalIdentity
        toolkit.accessibilityClock = originalClock
        toolkit.canAuditThisBuild = { true }
        UserDefaults.scyther.setValue(originalLiveEnabled, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        // Cancels anything this test scheduled and empties the overlay, so no pending work item
        // fires into the next test.
        UserDefaults.scyther.setValue(false, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.showAccessibilityAudit()
        toolkit.canAuditThisBuild = originalCanAudit
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

    // MARK: - The Debounce

    /// The debounce's whole job: however many things trigger a re-audit inside its window, one
    /// pass runs.
    ///
    /// Everything else in this file reads `hasPendingAccessibilityAudit` and never lets a work item
    /// fire, so nothing asserted that `pendingAccessibilityAudit?.cancel()` is there at all —
    /// deleting it turns five scroll or layout triggers into five full tree walks and five window
    /// snapshots, on the main thread, and left every test green. This one waits for the work item
    /// and counts the passes.
    func testEveryTriggerInsideTheDebounceWindowIsOnePass() async {
        var passes = 0
        toolkit.runAccessibilityPass = {
            passes += 1
            return self.result("app")
        }

        for _ in 0..<5 { toolkit.scheduleAccessibilityReaudit() }
        XCTAssertEqual(passes, 0, "nothing runs synchronously; the point of the debounce is to wait")

        let ran = expectation(description: "the debounced pass runs")
        DispatchQueue.main.asyncAfter(deadline: .now() + InterfaceToolkit.AccessibilityAuditDebounceInterval * 3) {
            ran.fulfill()
        }
        await fulfillment(of: [ran], timeout: 5)

        XCTAssertEqual(passes, 1, "five triggers inside one debounce window are one pass, not five")
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
    }

    /// The three intervals the feature's cost is expressed in, as literals.
    ///
    /// Named in no test until now: any of them could have been `0.001` — a pass on every run-loop
    /// turn — or `60`, with the whole suite green and the README wrong.
    func testTheFeaturesIntervalsAreTheNumbersTheDocumentationQuotes() {
        XCTAssertEqual(InterfaceToolkit.AccessibilityAuditDebounceInterval, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(InterfaceToolkit.AccessibilityScreenPollInterval, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(InterfaceToolkit.AccessibilityAuditMaximumDeferral, 2, accuracy: 0.000_1)
    }

    /// With live mode off there is nothing to keep in step with, so a stray trigger — the overlay's
    /// own frame hook firing after the developer switched the feature off — must schedule nothing.
    /// Without the guard, Scyther rasterises the user's window every half-second for a feature
    /// nobody has switched on.
    func testNothingIsScheduledWithLiveModeSwitchedOff() {
        UserDefaults.scyther.setValue(false, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)

        toolkit.scheduleAccessibilityReaudit()
        toolkit.windowDidBecomeVisibleNotification(notification: NSNotification(name: .init("test"), object: nil))
        toolkit.pollAccessibilityScreen()

        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
    }

    /// Switching live mode off has to leave nothing behind: no boxes, no pending pass, no timer.
    /// A stale box left over the app after the developer turned the feature off reads as a bug in
    /// the audit rather than as the setting they chose.
    func testSwitchingLiveModeOffClearsTheBoxesAndCancelsWhatWasScheduled() {
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.showAccessibilityAudit()
        toolkit.runAccessibilityAudit()
        toolkit.scheduleAccessibilityReaudit()
        XCTAssertFalse(toolkit.accessibilityAuditView.findings.isEmpty)
        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit)
        XCTAssertTrue(toolkit.isPollingAccessibilityScreen)

        UserDefaults.scyther.setValue(false, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.showAccessibilityAudit()

        XCTAssertTrue(toolkit.accessibilityAuditView.findings.isEmpty, "the boxes go with the setting")
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
        XCTAssertFalse(toolkit.isPollingAccessibilityScreen)
        XCTAssertTrue(toolkit.accessibilityAuditView.isHidden)
    }

    // MARK: - The Notifications Are Actually Observed

    /// Registers `InterfaceToolkit`'s observers once for this process.
    ///
    /// The tests below post through `NotificationCenter.default` rather than calling a handler, so
    /// the registration itself is what they are about — and a hostless test process may never have
    /// run `Scyther.start()`, which is what registers them in production. Once, and statically, so
    /// a per-test `setUp` cannot pile duplicate observations onto a singleton nothing unregisters.
    private static let observersRegistered: Void = {
        MainActor.assumeIsolated { InterfaceToolkit.instance.registerForNotitfcations() }
    }()

    /// Removing the `addObserver` line for `coverageDidChangeNotification` leaves the audit's boxes
    /// stroked across Scyther's own report — the exact defect the notification was added for — and
    /// every existing test green, because they all call the handler directly.
    func testTheCoverageNotificationIsObservedAndNotOnlyHandled() async {
        _ = Self.observersRegistered
        toolkit.isScytherCoveringScreen = { false }

        NotificationCenter.default.post(name: ScytherPresentation.coverageDidChangeNotification, object: nil)
        await Task.yield()

        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit,
                      "Scyther's screen going away must schedule the pass it suppressed")
    }

    /// The same for `UIWindow.didBecomeVisibleNotification`, whose handler had no test of any kind:
    /// a window finishing its first appearance is one more moment the layout may just have settled.
    func testTheWindowNotificationIsObservedAndNotOnlyHandled() async {
        _ = Self.observersRegistered

        NotificationCenter.default.post(name: UIWindow.didBecomeVisibleNotification, object: nil)
        await Task.yield()

        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit)
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

        XCTAssertEqual(toolkit.accessibilityPassForReport()?.result.findings.map(\.elementName), ["app"])
    }

    /// With nothing of Scyther's on screen there is no sheet to measure through, so the report has
    /// no reason to prefer an older pass to one of its own.
    func testTheReportTakesItsOwnPassWhenNothingIsCoveringTheApp() {
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.runAccessibilityAudit()

        XCTAssertNil(toolkit.accessibilityPassForReport())
    }

    /// A seeded pass is always older than the screen reading it — no pass can run while Scyther
    /// covers the app — so it has to carry the moment it was taken. Without one the report presents
    /// a pass from before a scroll as the current state of the app.
    func testTheSeededPassCarriesTheMomentItWasTaken() {
        var clock = Date(timeIntervalSince1970: 5_000)
        toolkit.accessibilityClock = { clock }
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.runAccessibilityAudit()

        clock = clock.addingTimeInterval(30)
        toolkit.isScytherCoveringScreen = { true }

        XCTAssertEqual(toolkit.accessibilityPassForReport()?.takenAt, Date(timeIntervalSince1970: 5_000))
    }

    // MARK: - A Pass Always Eventually Runs

    /// The poll's period and the debounce's period are both half a second, so a screen whose
    /// controller chain changes on every poll cancelled the pending pass at about the instant it was
    /// due, over and over: the boxes never updated, with no spinner and no banner. Nothing capped
    /// the number of consecutive cancellations.
    func testAPassIsNotDeferredForever() {
        var clock = Date(timeIntervalSince1970: 0)
        toolkit.accessibilityClock = { clock }

        toolkit.scheduleAccessibilityReaudit()
        let first = toolkit.pendingAccessibilityAuditDeadline
        XCTAssertNotNil(first)

        // Inside the floor, a fresh trigger still replaces the pending pass: that is the debounce
        // doing its job.
        clock = clock.addingTimeInterval(0.5)
        toolkit.scheduleAccessibilityReaudit()
        let deferred = toolkit.pendingAccessibilityAuditDeadline
        XCTAssertNotEqual(deferred, first, "inside the floor a trigger still coalesces")

        // Past it, the pass that has been waiting is left alone rather than cancelled again.
        clock = clock.addingTimeInterval(InterfaceToolkit.AccessibilityAuditMaximumDeferral)
        toolkit.scheduleAccessibilityReaudit()

        XCTAssertEqual(toolkit.pendingAccessibilityAuditDeadline, deferred,
                       "a pass deferred past the floor must be left to run")
    }

    /// The floor is measured from the first trigger of a run of them, not from the last, and it
    /// resets once a pass has actually run.
    func testTheDeferralFloorRestartsAfterAPassRuns() {
        var clock = Date(timeIntervalSince1970: 0)
        toolkit.accessibilityClock = { clock }
        toolkit.runAccessibilityPass = { self.result("app") }

        toolkit.scheduleAccessibilityReaudit()
        clock = clock.addingTimeInterval(InterfaceToolkit.AccessibilityAuditMaximumDeferral + 1)
        toolkit.runAccessibilityAudit()

        toolkit.scheduleAccessibilityReaudit()
        let first = toolkit.pendingAccessibilityAuditDeadline
        clock = clock.addingTimeInterval(0.1)
        toolkit.scheduleAccessibilityReaudit()

        XCTAssertNotEqual(toolkit.pendingAccessibilityAuditDeadline, first,
                          "the clock on the floor starts again once a pass has run")
    }

    // MARK: - Production Builds

    /// The capture and the accessibility walk are blocked on a build the audit may not run on; the
    /// apparatus around them was not. A shipping app built with `allowProductionBuilds: true` and
    /// `liveEnabled` persisted ran a repeating half-second `Timer`, walked a hundred-deep controller
    /// chain two to four times a second, and left a full-screen overlay in the app's hit-testing —
    /// all of it feeding a pass whose only possible outcome was an empty result.
    func testNothingIsInstalledOrScheduledOnABuildTheAuditMayNotRunOn() {
        toolkit.canAuditThisBuild = { false }

        toolkit.showAccessibilityAudit()

        XCTAssertFalse(toolkit.isPollingAccessibilityScreen,
                       "no run-loop wakeups for a result that is empty by construction")
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
        XCTAssertTrue(toolkit.accessibilityAuditView.isHidden,
                      "and nothing left over the app for every touch to be hit-tested against")
    }

    /// Every trigger goes through the same schedule, so the notification observers registered at
    /// launch must not get round the guard either.
    func testNoTriggerCanScheduleAPassOnABuildTheAuditMayNotRunOn() {
        toolkit.canAuditThisBuild = { false }

        toolkit.windowDidBecomeVisibleNotification(notification: NSNotification(name: .init("test"), object: nil))
        toolkit.scheduleAccessibilityReaudit()

        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
    }

    /// The build the audit exists for is untouched.
    func testTheOverlayStillRunsOnABuildTheAuditMayRunOn() {
        toolkit.canAuditThisBuild = { true }

        toolkit.showAccessibilityAudit()

        XCTAssertTrue(toolkit.isPollingAccessibilityScreen)
        XCTAssertFalse(toolkit.accessibilityAuditView.isHidden)
    }

    // MARK: - What A Pass Costs

    /// A pass reads tens of thousands of Objective-C properties, each returning through
    /// `objc_claimAutoreleasedReturnValue`, and every `subviews` read bridges an autoreleased
    /// `NSArray`. All of it ran inside one main-actor turn with no pool, so the whole lot sat in
    /// the run loop's own pool alongside the window snapshot until the turn ended.
    func testAPassDrainsItsOwnAutoreleasedObjects() {
        weak var probe: NSObject?
        toolkit.runAccessibilityPass = {
            let object = NSObject()
            probe = object
            // What every Objective-C property read in the walk does to the enclosing pool.
            _ = Unmanaged.passRetained(object).autorelease()
            return self.result("app")
        }

        toolkit.runAccessibilityAudit()

        XCTAssertNil(probe, "a pass must drain its own autoreleased objects rather than piling them up")
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
