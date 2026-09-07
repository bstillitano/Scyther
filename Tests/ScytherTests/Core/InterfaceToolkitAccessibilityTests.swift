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
    nonisolated(unsafe) private var originalReportPass: (@MainActor () -> AccessibilityAuditor.Result)!
    nonisolated(unsafe) private var originalCoverage: (@MainActor () -> Bool)!
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
        originalReportPass = toolkit.runAccessibilityReportPass
        originalCoverage = toolkit.isScytherCoveringScreen
        originalClock = toolkit.accessibilityClock
        originalCanAudit = toolkit.canAuditThisBuild
        toolkit.isScytherCoveringScreen = { false }
        // `AppEnvironment.isTestCase` is unconditionally true here, so the real predicate would
        // refuse every pass and nothing below would ever be scheduled. Each test that is *about*
        // the refusal drives this seam itself.
        toolkit.canAuditThisBuild = { true }
        // A clean slate, through the same door production uses: switching live mode off cancels any
        // pending pass, stops watching layout and forgets a layout already counted this turn. The
        // last of those matters most — `hasNotedALayoutThisTurn` is coalescing state whose reset is
        // one run-loop turn out, so a test that inherited it set would silently suppress the very
        // trigger it was written to assert.
        UserDefaults.scyther.setValue(false, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.showAccessibilityAudit()
        UserDefaults.scyther.setValue(true, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.accessibilityAuditView.findings = []
    }

    override func tearDown() async throws {
        toolkit.runAccessibilityPass = originalPass
        toolkit.runAccessibilityReportPass = originalReportPass
        toolkit.isScytherCoveringScreen = originalCoverage
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

    /// A view outside Scyther's own overlays laying out is the app's content changing, and it must
    /// re-audit.
    ///
    /// The defect this replaces: the trigger was a poll of the *showing view-controller chain*, and
    /// in a SwiftUI app that chain does not move for a `TabView` switch, a `NavigationStack` push or
    /// a `List` scroll — it is all one hosting controller. Measured on a simulator, live mode took
    /// one pass at launch and never another, however much the app was navigated.
    func testTheAppLayingSomethingOutSchedulesAPass() {
        toolkit.runAccessibilityPass = { self.result("app") }

        toolkit.appViewDidLayout(UIView())

        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit)
    }

    /// And it reaches that hook through the swizzle production actually installs, not only through a
    /// method a test can call directly.
    ///
    /// `InterfaceToolkit.swizzleLayout` is the one wire between UIKit laying a view out and this
    /// feature noticing. Deleting the call from `UIView.swizzledLayoutSubviews()` leaves every other
    /// test in this file green and the live overlay frozen at launch, which is precisely the bug.
    func testARealLayoutPassReachesTheScheduler() {
        // The same installation `InterfaceToolkit.start()` performs. Idempotent — it is a `static
        // let` — and inert unless the debug-border or view-size settings are on, which they are not.
        toolkit.swizzleLayout()
        InterfaceToolkit.isObservingAppLayout = true
        defer { InterfaceToolkit.isObservingAppLayout = false }

        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.setNeedsLayout()
        view.layoutIfNeeded()

        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit)
    }

    /// A layout pass lays out every view that needs it — hundreds of them while a scroll is
    /// tracking — and that has to cost one schedule, not hundreds.
    ///
    /// The debounce would collapse them into a single *pass* either way; what this is about is the
    /// `DispatchWorkItem` cancelled, allocated and armed on each call, per view, per frame.
    func testABurstOfLayoutsInOneTurnIsCountedOnce() {
        toolkit.runAccessibilityPass = { self.result("app") }

        toolkit.appViewDidLayout(UIView())
        let first = toolkit.pendingAccessibilityAuditDeadline
        XCTAssertTrue(toolkit.hasNotedALayoutThisTurn)

        toolkit.accessibilityClock = { Date(timeIntervalSince1970: 9_999) }
        for _ in 0..<200 { toolkit.appViewDidLayout(UIView()) }

        XCTAssertEqual(toolkit.pendingAccessibilityAuditDeadline, first,
                       "the rest of the layout pass must not re-arm the debounce 200 times")
    }

    /// And however many layouts arrive, one pass runs.
    ///
    /// The end-to-end version of the debounce's contract, driven by the trigger that now feeds it:
    /// a burst of layouts is one 121ms pass once the screen settles, not one per layout.
    func testABurstOfLayoutsIsOnePassAndNotMany() async {
        var passes = 0
        toolkit.runAccessibilityPass = {
            passes += 1
            return self.result("app")
        }

        for _ in 0..<5 { toolkit.appViewDidLayout(UIView()) }
        XCTAssertEqual(passes, 0, "nothing runs synchronously; the point of the debounce is to wait")

        let ran = expectation(description: "the debounced pass runs")
        DispatchQueue.main.asyncAfter(deadline: .now() + InterfaceToolkit.AccessibilityAuditDebounceInterval * 3) {
            ran.fulfill()
        }
        await fulfillment(of: [ran], timeout: 5)

        XCTAssertEqual(passes, 1, "a burst of layouts is one pass, not many")
    }

    /// A pass draws boxes, and drawing is layout — so a pass that counted its own drawing would
    /// schedule the next one for ever.
    ///
    /// Everything the live overlay puts on screen lives inside ``TopLevelViewsWrapper``: the boxes,
    /// the count pill, the flash layer, and the grid and FPS overlays beside them. A layout in there
    /// is refused, which is what makes the loop impossible rather than merely short.
    ///
    /// The second line of defence — a pass that found what the last one found repaints nothing at
    /// all, so there is no drawing for a layout to come out of — is
    /// `AccessibilityAuditOverlayViewTests.testAPassThatFoundTheSameThingsDoesNotRepaintTheOverlay()`.
    func testDrawingTheFindingsCannotScheduleAnotherPass() {
        toolkit.runAccessibilityPass = { self.result("app") }
        // Production parents the overlay in `setupAccessibilityAudit()`, which does not run in a
        // hostless test process.
        if toolkit.accessibilityAuditView.superview !== toolkit.topLevelViewsWrapper {
            toolkit.topLevelViewsWrapper.addSubview(toolkit.accessibilityAuditView)
        }

        toolkit.runAccessibilityAudit()
        XCTAssertFalse(toolkit.accessibilityAuditView.findings.isEmpty, "a pass drew something")

        toolkit.appViewDidLayout(toolkit.accessibilityAuditView)
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit, "the boxes must not re-audit themselves")

        toolkit.appViewDidLayout(toolkit.accessibilityAuditView.reportButton)
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit, "nor may the pill's own count")

        toolkit.appViewDidLayout(toolkit.topLevelViewsWrapper)
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit, "nor the wrapper they all sit in")
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

    /// The two intervals the feature's cost is expressed in, as literals.
    ///
    /// Named in no test until now: either could have been `0.001` — a pass on every run-loop
    /// turn — or `60`, with the whole suite green and the README wrong.
    func testTheFeaturesIntervalsAreTheNumbersTheDocumentationQuotes() {
        XCTAssertEqual(InterfaceToolkit.AccessibilityAuditDebounceInterval, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(InterfaceToolkit.AccessibilityAuditMaximumDeferral, 2, accuracy: 0.000_1)
    }

    /// With live mode off there is nothing to keep in step with, so no trigger may schedule
    /// anything — and the app laying out, which now happens on every frame of every scroll in every
    /// app that has ever linked Scyther, must not even reach the scheduler to be turned away.
    func testNothingIsScheduledWithLiveModeSwitchedOff() {
        UserDefaults.scyther.setValue(false, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.showAccessibilityAudit()

        XCTAssertFalse(InterfaceToolkit.isObservingAppLayout,
                       "a layout must be ruled out on one static load, not on a UserDefaults read")

        toolkit.scheduleAccessibilityReaudit()
        toolkit.windowDidBecomeVisibleNotification(notification: NSNotification(name: .init("test"), object: nil))
        InterfaceToolkit.appViewDidLayout(UIView())
        toolkit.appViewDidLayout(UIView())

        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
    }

    /// Switching live mode off has to leave nothing behind: no boxes, no pending pass, and nothing
    /// still watching the app lay out.
    /// A stale box left over the app after the developer turned the feature off reads as a bug in
    /// the audit rather than as the setting they chose.
    func testSwitchingLiveModeOffClearsTheBoxesAndCancelsWhatWasScheduled() {
        toolkit.runAccessibilityPass = { self.result("app") }
        toolkit.showAccessibilityAudit()
        toolkit.runAccessibilityAudit()
        toolkit.scheduleAccessibilityReaudit()
        XCTAssertFalse(toolkit.accessibilityAuditView.findings.isEmpty)
        XCTAssertTrue(toolkit.hasPendingAccessibilityAudit)
        XCTAssertTrue(InterfaceToolkit.isObservingAppLayout)

        UserDefaults.scyther.setValue(false, forKey: AccessibilityAudit.LiveEnabledDefaultsKey)
        toolkit.showAccessibilityAudit()

        XCTAssertTrue(toolkit.accessibilityAuditView.findings.isEmpty, "the boxes go with the setting")
        XCTAssertFalse(toolkit.hasPendingAccessibilityAudit)
        XCTAssertFalse(InterfaceToolkit.isObservingAppLayout)
        XCTAssertFalse(toolkit.hasNotedALayoutThisTurn)
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

    // MARK: - The Pass The Report Is Given

    /// The report has to be able to measure contrast, and contrast is measured from the pixels in
    /// the window. From the moment the report's sheet is up those pixels are Scyther's dimming of
    /// the app, so the only moment a report pass can be honest is the one between the developer
    /// tapping the pill and the sheet rising — which is where this runs.
    func testTheReportPassIsTakenWhileTheAppIsStillOnScreen() {
        var passes = 0
        toolkit.runAccessibilityReportPass = {
            passes += 1
            return self.result("report")
        }

        toolkit.takeAccessibilityPassForReport()

        XCTAssertEqual(passes, 1)
        toolkit.isScytherCoveringScreen = { true }
        XCTAssertEqual(toolkit.accessibilityPassForReport()?.result.findings.map(\.elementName), ["report"])
    }

    /// And it does not run once Scyther is already in front of the app: everything it measured
    /// would be Scyther's own sheet, which is the whole reason the pass is taken early.
    func testNoReportPassIsTakenOnceScytherIsAlreadyCoveringTheApp() {
        var passes = 0
        toolkit.runAccessibilityReportPass = {
            passes += 1
            return self.result("report")
        }
        toolkit.isScytherCoveringScreen = { true }

        toolkit.takeAccessibilityPassForReport()

        XCTAssertEqual(passes, 0)
    }

    /// The pill counts what live mode checks and the report counts what the report checked. A
    /// report pass therefore seeds the report in full but hands the overlay only the findings from
    /// the two checks a live pass runs, so the count on screen never silently changes meaning
    /// depending on how the developer last opened a screen.
    func testTheOverlayKeepsCountingOnlyWhatALivePassChecks() {
        toolkit.runAccessibilityReportPass = {
            AccessibilityAuditor.Result(
                findings: [self.finding(.missingLabel, "button"), self.finding(.contrast, "caption")],
                didHitLimit: false,
                checksRun: Set(AccessibilityCheck.allCases)
            )
        }

        toolkit.takeAccessibilityPassForReport()

        XCTAssertEqual(toolkit.accessibilityAuditView.findings.map(\.elementName), ["button"])
        toolkit.isScytherCoveringScreen = { true }
        XCTAssertEqual(toolkit.accessibilityPassForReport()?.result.findings.count, 2,
                       "the report itself still opens onto the whole pass")
    }

    /// A build the audit may not run on must not be snapshotted either, and this is a second door
    /// into a pass that ``runAccessibilityAudit()``'s own guard does not cover.
    func testNoReportPassIsTakenOnABuildTheAuditMayNotRunOn() {
        toolkit.canAuditThisBuild = { false }
        var passes = 0
        toolkit.runAccessibilityReportPass = {
            passes += 1
            return self.result("report")
        }

        toolkit.takeAccessibilityPassForReport()

        XCTAssertEqual(passes, 0)
    }

    /// One finding of a given check, so a pass's contents can be told apart by check.
    ///
    /// - Parameters:
    ///   - check: Which check produced it.
    ///   - name: What to call the element.
    /// - Returns: The finding.
    private func finding(_ check: AccessibilityCheck, _ name: String) -> AccessibilityFinding {
        AccessibilityFinding(check: check,
                             severity: .warning,
                             frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                             elementName: name,
                             detail: "detail")
    }

    // MARK: - A Pass Always Eventually Runs

    /// A trigger arriving one debounce after the last one cancels the pending pass at about the
    /// instant it was due, over and over: the boxes never update, with no spinner and no banner.
    /// Nothing capped the number of consecutive cancellations. It is the live case for any screen
    /// that never stops laying out — a spinner, a video layer, an animation that does not settle.
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

    /// What that floor costs, said out loud, because the trigger is now the app laying out.
    ///
    /// A scroll lays out on every frame it tracks, so an unbroken scroll longer than the floor plus
    /// a debounce takes a live pass — about 121ms of main thread — while the screen is still moving.
    /// That is the deliberate exception to "a pass lands only once the screen stops": without it,
    /// a screen that never settles never gets a pass at all.
    func testAnUnbrokenStreamOfLayoutsStillLetsAPassThrough() {
        var clock = Date(timeIntervalSince1970: 0)
        toolkit.accessibilityClock = { clock }

        toolkit.appViewDidLayout(UIView())
        let due = toolkit.pendingAccessibilityAuditDeadline
        XCTAssertEqual(due, Date(timeIntervalSince1970: InterfaceToolkit.AccessibilityAuditDebounceInterval))

        // Every frame of a scroll, for longer than the floor. Each one is a fresh turn, so each one
        // reaches the scheduler rather than being coalesced away.
        for _ in 0..<200 {
            clock = clock.addingTimeInterval(1.0 / 60.0)
            toolkit.forgetTheLayoutNotedThisTurn()
            toolkit.appViewDidLayout(UIView())
        }

        XCTAssertNotNil(toolkit.pendingAccessibilityAuditDeadline)
        XCTAssertLessThanOrEqual(toolkit.pendingAccessibilityAuditDeadline ?? .distantFuture,
                                 Date(timeIntervalSince1970: InterfaceToolkit.AccessibilityAuditMaximumDeferral
                                      + InterfaceToolkit.AccessibilityAuditDebounceInterval),
                                 "a scroll that never stops must still be audited at the floor")
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

        XCTAssertFalse(InterfaceToolkit.isObservingAppLayout,
                       "no per-frame work for a result that is empty by construction")
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

        XCTAssertTrue(InterfaceToolkit.isObservingAppLayout)
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
