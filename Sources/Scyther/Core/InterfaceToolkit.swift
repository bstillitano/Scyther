//
//  InterfaceToolkit.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if !os(macOS)
import NotificationCenter
import UIKit

/// Manages UI debugging tools and overlays.
///
/// `InterfaceToolkit` is an internal singleton that coordinates various UI debugging
/// features including:
/// - Touch visualisation
/// - Grid overlay
/// - Slow animations
/// - View frame debugging
///
/// This class is used internally by ``Interface`` and should not be accessed directly.
/// Use ``Scyther/interface`` instead.
@MainActor
public final class InterfaceToolkit: NSObject, Sendable {
    // MARK: - Static Data (nonisolated for cross-thread access)
    nonisolated internal static let DebugBordersChangeNotification = NSNotification.Name("DebugBordersChangeNotification")
    nonisolated internal static let DebugSizesChangeNotification = NSNotification.Name("DebugSizesChangeNotification")
    nonisolated internal static let VisualiseTouchesChangeNotification = NSNotification.Name("VisualiseTouchesChangeNotification")
    nonisolated internal static let SlowAnimationsUserDefaultsKey = "Scyther_Interface_Toolkit_Slow_Animations_Enabled"
    nonisolated internal static let ViewFramesUserDefaultsKey = "Scyther_Interface_Toolkit_View_Borders_Enabled"
    nonisolated internal static let ViewSizesUserDefaultsKey = "Scyther_Interface_Toolkit_View_Sizes_Enabled"
    nonisolated internal static let VisualiseTouchesUserDefaultsKey = "Scyther_Interface_Toolkit_Visualise_Touches_Enabled"

    /// How long to wait, after the last thing that might have changed the screen's layout,
    /// before re-auditing it in live mode. A single tap, rotation, or navigation push can
    /// trigger several layout passes in quick succession; without a debounce each one would
    /// start its own snapshot-and-walk, which is exactly the wasted, overlapping work
    /// ``scheduleAccessibilityReaudit()`` exists to avoid.
    nonisolated internal static let AccessibilityAuditDebounceInterval: TimeInterval = 0.5

    /// How often, while live mode is on, Scyther asks whether the app has navigated somewhere else.
    ///
    /// See ``pollAccessibilityScreen()`` for why the question is asked on a clock rather than
    /// answered by a notification. Half a second, matching
    /// ``AccessibilityAuditDebounceInterval``, so the worst case between arriving on a screen and
    /// its boxes being right is one poll plus one debounce.
    nonisolated internal static let AccessibilityScreenPollInterval: TimeInterval = 0.5

    /// The longest a pending pass may be deferred by fresh triggers before it is left to run.
    ///
    /// The poll's period and the debounce's period are the same half a second, and every poll that
    /// sees a changed controller chain cancels the pending pass and schedules a fresh one exactly
    /// one debounce out. On a screen whose chain changes on every poll — an auto-advancing
    /// `UIPageViewController`, a media player recreating its controller, a SwiftUI screen whose
    /// hosting children churn — the pass was therefore cancelled at about the instant it was due,
    /// over and over, and the boxes never updated: no spinner, no banner, and no way to force a
    /// pass short of opening the report. Nothing capped the number of consecutive cancellations.
    ///
    /// Two seconds, measured from the *first* trigger of a run rather than the last, so a genuine
    /// burst still coalesces into one pass while an endless stream cannot starve it. Past the floor
    /// the pending pass is left alone rather than replaced: a pass of a screen two seconds stale is
    /// worth incomparably more than a pass that never happens.
    nonisolated internal static let AccessibilityAuditMaximumDeferral: TimeInterval = 2

    /// Private Init to Stop re-initialisation and allow singleton creation.
    override private init() { }

    /// An initialised, shared instance of the `InterfaceToolkit` class.
    static let instance = InterfaceToolkit()

    // MARK: - UI Elements
    public var touchVisualiser: TouchVisualiser = TouchVisualiser.instance
    internal var gridOverlayView: GridOverlayView = GridOverlayView()
    internal var fpsCounterView: FPSCounterView = FPSCounterView()
    internal var accessibilityAuditView: AccessibilityAuditOverlayView = AccessibilityAuditOverlayView()
    internal var topLevelViewsWrapper: TopLevelViewsWrapper = TopLevelViewsWrapper()

    /// The pending, debounced re-audit scheduled by ``scheduleAccessibilityReaudit()``, kept so
    /// a second trigger arriving before it fires can cancel and replace it rather than stacking
    /// up a second audit behind the first.
    private var pendingAccessibilityAudit: DispatchWorkItem?

    /// Whether a debounced re-audit is waiting to run. Readable so a test can assert that a
    /// trigger reached ``scheduleAccessibilityReaudit()`` without waiting half a second for the
    /// audit itself, which in a test host would do nothing anyway.
    internal var hasPendingAccessibilityAudit: Bool { pendingAccessibilityAudit != nil }

    /// Watches for the app navigating somewhere else while live mode is on. See
    /// ``pollAccessibilityScreen()``.
    private var accessibilityScreenTimer: Timer?

    /// The screen the last poll saw, so a change is noticed once rather than every half second
    /// until the next audit lands.
    private var lastAccessibilityScreenIdentity: [ObjectIdentifier] = []

    /// When ``lastUncoveredAccessibilityResult`` was taken.
    private var lastUncoveredAccessibilityResultTakenAt: Date?

    /// When the pending re-audit is due, or `nil` when none is pending.
    internal private(set) var pendingAccessibilityAuditDeadline: Date?

    /// When the first of the current run of triggers arrived, or `nil` when no pass is pending.
    ///
    /// The clock ``AccessibilityAuditMaximumDeferral`` is measured against. Cleared whenever a pass
    /// actually runs, so the floor is about one run of deferrals rather than about the process.
    private var accessibilityAuditFirstScheduledAt: Date?

    /// Reads the current time.
    ///
    /// Injected for the same reason `AccessibilityAuditor.now` is: the deferral floor and the
    /// seeded pass's age are both statements about elapsed time, and a test that drove them with
    /// the wall clock would either sleep or flake.
    internal var accessibilityClock: @MainActor () -> Date = Date.init

    /// Whether this build may run the audit at all.
    ///
    /// The same predicate ``AccessibilityAudit/auditKeyWindow()`` refuses on, asked one layer out.
    /// That guard covers the pixels and the accessibility walk, which is what it was written for,
    /// and covers none of the apparatus around them: a host shipping
    /// `Scyther.start(allowProductionBuilds: true)` with ``AccessibilityAudit/liveEnabled``
    /// persisted — the exact combination that guard names as the hole — installed a repeating
    /// half-second `Timer` on the main run loop in `.common` mode for the life of the process, a
    /// hundred-deep controller-chain walk two to four times a second, a `DispatchWorkItem` on every
    /// navigation, and a full-screen overlay consulted on every touch, all to feed a function whose
    /// only possible answer was an empty result. Nothing may be installed, observed or scheduled in
    /// a build where the audit cannot run.
    ///
    /// Injected because `AppEnvironment.isTestCase` is unconditionally `true` under XCTest and
    /// `isAppStore` unconditionally `false`, so neither branch could otherwise be reached by a test.
    internal var canAuditThisBuild: @MainActor () -> Bool = {
        AccessibilityAudit.canAuditKeyWindow(isTestCase: AppEnvironment.isTestCase,
                                             isAppStore: AppEnvironment.isAppStore)
    }

    /// Whether the screen poll is installed right now. Readable so a test can assert that a build
    /// the audit may not run on is not waking the run loop.
    internal var isPollingAccessibilityScreen: Bool { accessibilityScreenTimer != nil }

    /// The most recent pass taken while nothing of Scyther's was covering the app.
    ///
    /// This is the only honest pass there is: it is the one whose contrast was measured against
    /// the app's own pixels and whose geometry came through no sheet of Scyther's. The report
    /// screen opens onto it — see ``accessibilityResultForReport()`` — so the count on the pill and
    /// the report that pill opens describe the same pass rather than two different ones.
    private var lastUncoveredAccessibilityResult: AccessibilityAuditor.Result?

    /// Runs one pass of the audit. Replaced by a test, which has no window worth walking.
    internal var runAccessibilityPass: @MainActor () -> AccessibilityAuditor.Result = {
        AccessibilityAudit.instance.auditKeyWindow(purpose: .live)
    }

    /// Runs one *report* pass — every check the developer has switched on, contrast included.
    ///
    /// Separate from ``runAccessibilityPass`` because the two are taken at different moments for
    /// different reasons, and only one of them may afford a window snapshot. Injected for the same
    /// reason as its sibling: a hostless test process has no key window to walk.
    internal var runAccessibilityReportPass: @MainActor () -> AccessibilityAuditor.Result = {
        AccessibilityAudit.instance.auditKeyWindow(purpose: .report)
    }

    /// Reads which screen the app is showing. Replaced by a test.
    ///
    /// A seam in the same style as `ScytherPresentation.isCoveringScreenProbe` and
    /// `AccessibilityAuditor.now`: a hostless `xctest` process has no key window, so the real
    /// reader answers with an empty array forever and a test that could not replace it would be
    /// asserting that nothing ever changes — which is precisely the bug.
    internal var accessibilityScreenIdentityProbe: @MainActor () -> [ObjectIdentifier] = {
        InterfaceToolkit.accessibilityScreenIdentity(from: InterfaceToolkit.rootViewController)
    }

    /// Answers whether Scyther's own UI is in front of the app, at the moment it is asked.
    ///
    /// Asked *when a pass runs* rather than tracked from ``ScytherHostingController``'s appearance
    /// callbacks, which is the whole point of it being a closure that is called rather than a flag
    /// that is set. `viewDidAppear` fires after the presentation animation finishes, so a pass
    /// scheduled as Scyther's report was rising would look up a coverage flag that still said "the
    /// app" and walk a window that by then contained Scyther's own report — which is how the
    /// report came to list Scyther's own Close and Re-run buttons as 36 × 36pt touch-target errors.
    /// Injected so a test can drive both answers without a window and a live presentation.
    internal var isScytherCoveringScreen: @MainActor () -> Bool = { ScytherPresentation.isCoveringScreen }

    // MARK: - Data (nonisolated for UserDefaults access - thread-safe)
    internal nonisolated var visualiseTouches: Bool {
        get {
            UserDefaults.scyther.bool(forKey: InterfaceToolkit.VisualiseTouchesUserDefaultsKey)
        }
        set {
            UserDefaults.scyther.setValue(newValue, forKey: InterfaceToolkit.VisualiseTouchesUserDefaultsKey)
            NotificationCenter.default.post(name: InterfaceToolkit.VisualiseTouchesChangeNotification,
                                            object: newValue)
        }
    }
    internal nonisolated var showsViewBorders: Bool {
        get {
            UserDefaults.scyther.bool(forKey: InterfaceToolkit.ViewFramesUserDefaultsKey)
        }
        set {
            UserDefaults.scyther.setValue(newValue, forKey: InterfaceToolkit.ViewFramesUserDefaultsKey)
            NotificationCenter.default.post(name: InterfaceToolkit.DebugBordersChangeNotification,
                                            object: newValue)
        }
    }
    internal nonisolated var showsViewSizes: Bool {
        get {
            UserDefaults.scyther.bool(forKey: InterfaceToolkit.ViewSizesUserDefaultsKey)
        }
        set {
            UserDefaults.scyther.setValue(newValue, forKey: InterfaceToolkit.ViewSizesUserDefaultsKey)
            NotificationCenter.default.post(name: InterfaceToolkit.DebugSizesChangeNotification,
                                            object: newValue)
        }
    }
    internal nonisolated var slowAnimationsEnabled: Bool {
        get {
            UserDefaults.scyther.bool(forKey: InterfaceToolkit.SlowAnimationsUserDefaultsKey)
        }
        set {
            UserDefaults.scyther.setValue(newValue, forKey: InterfaceToolkit.SlowAnimationsUserDefaultsKey)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.setWindowSpeed()
                }
            }
        }
    }

    // MARK: - Lifecycle Notifications
    internal func registerForNotitfcations() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(newKeyWindowNotification(notification:)),
                                               name: UIWindow.didBecomeKeyNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(orientationDidChangeNotification(_:)),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActiveNotification(notification:)),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidBecomeVisibleNotification(notification:)),
                                               name: UIWindow.didBecomeVisibleNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scytherCoverageDidChangeNotification(notification:)),
                                               name: ScytherPresentation.coverageDidChangeNotification,
                                               object: nil)
    }

    internal func start() {
        registerForNotitfcations()

        /// Delaying here to allow UIWindow time to initialise.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupTopLevelViewsWrapper()
            self?.setupGridOverlay()
            self?.setupFPSCounter()
            self?.setupAccessibilityAudit()
            self?.setWindowSpeed()
            // Always swizzle so views can respond to debug toggle changes
            self?.swizzleLayout()
            if self?.visualiseTouches ?? false {
                TouchVisualiser.instance.start()
            }
        }
    }

    internal func swizzleLayout() {
        UIView.swizzleLayout
    }
    
    internal func swizzleWindow() {
        Self.keyWindow?.swizzle()
    }

    private func setupTopLevelViewsWrapper() {
        guard let keyWindow = Self.keyWindow else {
            logMessage("Scyther.InterfaceToolkit failed to setup the top level views wrapper. There is no keyWindow available.")
            return
        }
        addTopLevelViewsWrapperToWindow(window: keyWindow)
    }

    private static var keyWindow: UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }

    private func addTopLevelViewsWrapperToWindow(window: UIWindow) {
        topLevelViewsWrapper.superview?.removeObserver(self, forKeyPath: "layer.sublayers")
        window.addSubview(topLevelViewsWrapper)
        window.addObserver(self,
                           forKeyPath: "layer.sublayers",
                           options: [.new, .old],
                           context: nil)
    }

    @objc
    internal func newKeyWindowNotification(notification: NSNotification) {
        guard let window: UIWindow = notification.object as? UIWindow else {
            logMessage("Scyther.InterfaceToolkit failed to setup the top level views wrapper. There is no window available at UIWindow.didResignKeyNotification.object")
            return
        }
        addTopLevelViewsWrapperToWindow(window: window)
        setWindowSpeed()
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if object is UIWindow {
            Task { @MainActor in
                self.topLevelViewsWrapper.superview?.bringSubviewToFront(self.topLevelViewsWrapper)
            }
        }
    }
    
    @objc
    internal func applicationDidBecomeActiveNotification(notification: NSNotification) {
        swizzleWindow()
    }
    
    @objc
    internal func orientationDidChangeNotification(_ notification: Notification) {
        TouchVisualiser.instance.removeAllTouchViews()
    }

    /// A window finishing its first real appearance is one more moment the screen's layout may
    /// have just settled into its final shape — the case ``AccessibilityAuditOverlayView``'s own
    /// ``AccessibilityAuditOverlayView/updateFrame()`` hook cannot see, since nothing about *its*
    /// frame changed. Debouncing through the same ``scheduleAccessibilityReaudit()`` this notification
    /// shares with that hook means a rotation and a fresh window appearing in quick succession
    /// still only trigger one audit.
    @objc
    internal func windowDidBecomeVisibleNotification(notification: NSNotification) {
        scheduleAccessibilityReaudit()
    }

    /// Scyther's own UI has appeared over the app, or gone away again, so the live overlay has to
    /// decide afresh whether to draw.
    ///
    /// This is the only signal there is. A modal presentation changes nothing about the overlay's
    /// own frame, so ``AccessibilityAuditOverlayView/updateFrame()`` never runs and the boxes drawn
    /// for the app underneath would otherwise stay stroked across Scyther's own report. The redraw
    /// is immediate and deliberately *not* debounced: covering the app changes what should be drawn
    /// right now, and half a second of boxes over Scyther's report while a debounce runs down is
    /// exactly the thing being fixed.
    ///
    /// A re-audit *is* scheduled once Scyther's screen has gone, which is the opposite question
    /// with the opposite answer. No pass runs at all while Scyther covers the app — see
    /// ``runAccessibilityAudit()`` — so the findings waiting underneath are as old as the moment
    /// Scyther appeared, and they are also the only ones that ever had contrast measured against
    /// the app's own pixels. Coming back to them without re-auditing would leave the developer
    /// looking at boxes for whatever was on screen before they opened the menu.
    ///
    /// - Parameter notification: The posted notification. Unused: it carries no payload, because
    ///   whether Scyther covers the app is a fact about the whole presented chain rather than about
    ///   the one controller that just came or went.
    @objc
    internal func scytherCoverageDidChangeNotification(notification: NSNotification) {
        accessibilityAuditView.refreshForCoverageChange()
        guard !isScytherCoveringScreen() else { return }
        scheduleAccessibilityReaudit()
    }
}

// MARK: - Grid Overlay
extension InterfaceToolkit {
    @MainActor internal func setupGridOverlay() {
        gridOverlayView.opacity = CGFloat(GridOverlay.instance.opacity)
        gridOverlayView.isHidden = true
        gridOverlayView.gridSize = GridOverlay.instance.size
        gridOverlayView.colorScheme = GridOverlay.instance.colorScheme
        topLevelViewsWrapper.addTopLevelView(topLevelView: gridOverlayView)
        showGridOverlay()
    }

    @MainActor internal func showGridOverlay() {
        gridOverlayView.opacity = GridOverlay.instance.enabled ? CGFloat(GridOverlay.instance.opacity) : 0.0
        gridOverlayView.isHidden = !GridOverlay.instance.enabled
    }
}

// MARK: - FPS Counter
extension InterfaceToolkit {
    @MainActor internal func setupFPSCounter() {
        fpsCounterView.isHidden = true
        topLevelViewsWrapper.addTopLevelView(topLevelView: fpsCounterView)
        showFPSCounter()
    }

    @MainActor internal func showFPSCounter() {
        let enabled = FPSCounter.instance.enabled
        fpsCounterView.isHidden = !enabled
        if enabled {
            FPSCounter.instance.start()
        } else {
            FPSCounter.instance.stop()
        }
    }
}

// MARK: - Accessibility Audit
extension InterfaceToolkit {
    /// Installs the accessibility audit's overlay, mirroring ``setupGridOverlay()``.
    ///
    /// The overlay's ``AccessibilityAuditOverlayView/onFrameChanged`` hook is wired here, to
    /// ``scheduleAccessibilityReaudit()``, rather than the overlay reaching into
    /// `InterfaceToolkit` itself — see that hook's own documentation for why the dependency runs
    /// this direction. ``AccessibilityAuditOverlayView/onOpenReport`` is wired here for the same
    /// reason: the overlay knows only that its pill was tapped, and this is the one place that
    /// knows there is a report to open and who opens it.
    @MainActor internal func setupAccessibilityAudit() {
        // Nothing at all on a build the audit may not run on — not even the overlay, which is
        // otherwise left in the key window with a `point(inside:with:)` override consulted on every
        // touch for the life of the process. See ``canAuditThisBuild``.
        guard canAuditThisBuild() else { return }

        accessibilityAuditView.isHidden = true
        accessibilityAuditView.onFrameChanged = { [weak self] in
            self?.scheduleAccessibilityReaudit()
        }
        accessibilityAuditView.onOpenReport = {
            AccessibilityAuditReportPresenter.shared.openReport()
        }
        topLevelViewsWrapper.addTopLevelView(topLevelView: accessibilityAuditView)
        showAccessibilityAudit()
    }

    /// Shows or hides the accessibility audit overlay to match
    /// ``AccessibilityAudit/liveEnabled``, mirroring ``showGridOverlay()``.
    ///
    /// Switching live mode off clears ``AccessibilityAuditOverlayView/findings`` and cancels any
    /// re-audit already in flight — a stale box left on screen after the developer has turned
    /// the feature off would look like a bug in the audit rather than a setting they chose.
    @MainActor internal func showAccessibilityAudit() {
        let enabled = canAuditThisBuild() && AccessibilityAudit.instance.liveEnabled
        accessibilityAuditView.isHidden = !enabled
        if enabled {
            startAccessibilityScreenPolling()
            scheduleAccessibilityReaudit()
        } else {
            stopAccessibilityScreenPolling()
            pendingAccessibilityAudit?.cancel()
            pendingAccessibilityAudit = nil
            pendingAccessibilityAuditDeadline = nil
            accessibilityAuditFirstScheduledAt = nil
            lastUncoveredAccessibilityResult = nil
            lastUncoveredAccessibilityResultTakenAt = nil
            accessibilityAuditView.findings = []
        }
    }

    /// Starts asking, twice a second, whether the app has navigated somewhere else.
    ///
    /// Only while live mode is on: with the overlay off there is nothing to keep in step with, and
    /// a debugging toolkit has no business waking the run loop for a screen nobody is drawing.
    /// Scheduled in `.common` mode so a push that happens during a scroll is still noticed while
    /// the scroll is tracking.
    @MainActor private func startAccessibilityScreenPolling() {
        guard accessibilityScreenTimer == nil else { return }
        let timer = Timer(timeInterval: Self.AccessibilityScreenPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollAccessibilityScreen()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityScreenTimer = timer
    }

    /// Stops the poll and forgets which screen it last saw, so switching live mode back on
    /// re-audits rather than deciding nothing has changed since last time.
    @MainActor private func stopAccessibilityScreenPolling() {
        accessibilityScreenTimer?.invalidate()
        accessibilityScreenTimer = nil
        lastAccessibilityScreenIdentity = []
    }

    /// Schedules a re-audit when, and only when, the app is showing a different screen than it was
    /// at the last poll.
    ///
    /// ## Why a poll
    ///
    /// The live overlay used to follow exactly three things: a device rotation, a new `UIWindow`
    /// becoming visible, and live mode being switched on. A navigation push, a tab change, a
    /// swipe-back, the app presenting one of its own sheets — none of them reach any of those, so
    /// the boxes stayed pinned to a screen that had gone and the pill went on offering a report
    /// about it. UIKit posts no notification for "the app navigated": there is no public signal for
    /// a push, and the ones that exist (`UIWindow.didBecomeVisibleNotification`, the orientation
    /// notification) are the ones already wired up. The alternatives were swizzling
    /// `UIViewController.viewDidAppear` — a process-wide hook installed on the app under debug, for
    /// this one feature — or watching every frame, which is the cost this whole debounce exists to
    /// avoid.
    ///
    /// So the question is asked on a clock, and asked cheaply: ``accessibilityScreenIdentity(from:)``
    /// reads a handful of object pointers and allocates one small array, and only a *change* in the
    /// answer schedules anything. The audit itself still goes through the same debounce as
    /// everything else, so a push straight into a tab change is one pass, not two.
    ///
    /// ## What it still misses
    ///
    /// Anything that changes a screen without changing which view controllers are showing: a scroll,
    /// a table reload, a cell expanding, a form being filled in, a sheet whose contents swap
    /// underneath it. Those keep the boxes from the last pass until something else triggers one.
    @MainActor internal func pollAccessibilityScreen() {
        let identity = accessibilityScreenIdentityProbe()
        guard identity != lastAccessibilityScreenIdentity else { return }
        lastAccessibilityScreenIdentity = identity
        scheduleAccessibilityReaudit()
    }

    /// Which view controllers are showing, innermost last.
    ///
    /// Descends the way UIKit itself decides what is on screen: whatever is presented over a
    /// controller wins, then a navigation controller's top, a tab bar controller's selection, and
    /// otherwise the last child added. A push, a pop, a tab change, a modal appearing or being
    /// dismissed and a root swapped out from under everything all change this array; nothing else
    /// does, which is exactly the point.
    ///
    /// Identities rather than the controllers themselves, so nothing here keeps a dismissed screen
    /// alive, and a plain array rather than a hash, so a test can read what it found.
    ///
    /// - Parameter root: The key window's root view controller, or `nil` when there is no window.
    /// - Returns: The chain of controllers currently showing, in order.
    ///
    /// - SeeAlso: ``rootViewController``, which is where production gets `root` from.
    @MainActor internal static func accessibilityScreenIdentity(from root: UIViewController?) -> [ObjectIdentifier] {
        var identity: [ObjectIdentifier] = []
        var current = root
        var steps = 0
        while let controller = current, steps < AccessibilityAuditor.maximumDepth {
            identity.append(ObjectIdentifier(controller))
            current = visibleDescendant(of: controller)
            steps += 1
        }
        return identity
    }

    /// The key window's root view controller, which is where the screen the app is showing starts.
    @MainActor private static var rootViewController: UIViewController? {
        keyWindow?.rootViewController
    }

    /// The one controller below `controller` that the user is actually looking at.
    ///
    /// - Parameter controller: The controller to descend from.
    /// - Returns: The presented, top, selected or last child controller, or `nil` at the bottom.
    @MainActor private static func visibleDescendant(of controller: UIViewController) -> UIViewController? {
        if let presented = controller.presentedViewController { return presented }
        if let navigation = controller as? UINavigationController { return navigation.topViewController }
        if let tabs = controller as? UITabBarController { return tabs.selectedViewController }
        return controller.children.last
    }

    /// Coalesces however many things just triggered a re-audit into a single audit, run
    /// ``AccessibilityAuditDebounceInterval`` seconds from now.
    ///
    /// Built on a cancellable `DispatchWorkItem` rather than a repeating `Timer`: a `Timer` fires
    /// on a fixed schedule and has to be told each time whether to skip that firing, where a
    /// work item simply *is* the one pending audit — the previous one is cancelled and a fresh
    /// one takes its place, so there is only ever at most one audit scheduled no matter how many
    /// times this is called in quick succession. Does nothing when live mode is off, so a stray
    /// call from ``AccessibilityAuditOverlayView/onFrameChanged`` after the developer has
    /// switched the feature off does not schedule work that will just clear the overlay's
    /// already-empty findings a moment later.
    @MainActor internal func scheduleAccessibilityReaudit() {
        guard canAuditThisBuild(), AccessibilityAudit.instance.liveEnabled else { return }

        let now = accessibilityClock()
        // Past the floor, the pass that has been waiting is left exactly where it is. Cancelling it
        // again is what let a screen that changes on every poll defer it indefinitely.
        if let firstScheduledAt = accessibilityAuditFirstScheduledAt,
           pendingAccessibilityAudit != nil,
           now.timeIntervalSince(firstScheduledAt) >= Self.AccessibilityAuditMaximumDeferral {
            return
        }
        if accessibilityAuditFirstScheduledAt == nil {
            accessibilityAuditFirstScheduledAt = now
        }

        pendingAccessibilityAudit?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.runAccessibilityAudit()
        }
        pendingAccessibilityAudit = workItem
        pendingAccessibilityAuditDeadline = now.addingTimeInterval(Self.AccessibilityAuditDebounceInterval)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.AccessibilityAuditDebounceInterval, execute: workItem)
    }

    /// Runs the audit and hands its findings to the overlay.
    ///
    /// Only ``scheduleAccessibilityReaudit()`` calls this — nothing audits the window
    /// immediately, even when live mode is first switched on, so that the very first audit
    /// after enabling live mode gets the same debounce as every subsequent one and does not
    /// race a layout pass that has not finished yet.
    ///
    /// A pass that would land while Scyther's own UI is in front of the app is abandoned rather
    /// than run. Everything about such a pass is wrong in a way nothing downstream can undo: it
    /// walks a window that contains Scyther's own report, it measures the app through the sheet's
    /// transform, contrast is dropped because the pixels are Scyther's, and the honest findings
    /// taken a moment earlier — the ones the pill counted and the boxes describe — are overwritten
    /// by the poorer set. The coverage question is therefore asked *here*, when the pass is about
    /// to run, rather than remembered from when a controller appeared; the debounce means half a
    /// second routinely separates the two, and the report sheet rises inside that gap.
    /// ``scytherCoverageDidChangeNotification(notification:)`` schedules the pass that was skipped
    /// as soon as Scyther's screen goes away.
    @MainActor internal func runAccessibilityAudit() {
        pendingAccessibilityAudit = nil
        pendingAccessibilityAuditDeadline = nil
        accessibilityAuditFirstScheduledAt = nil
        guard !isScytherCoveringScreen() else { return }

        // Every accessibility property the walk reads returns through
        // `objc_claimAutoreleasedReturnValue`, and every `subviews` read bridges an autoreleased
        // `NSArray`. A pass makes tens of thousands of both, in one main-actor turn, so without a
        // pool of its own the lot sits in the run loop's alongside the window snapshot until the
        // turn ends — and in live mode a turn can hold several passes' worth.
        autoreleasepool {
            let result = runAccessibilityPass()
            lastUncoveredAccessibilityResult = result
            lastUncoveredAccessibilityResultTakenAt = accessibilityClock()
            accessibilityAuditView.findings = result.findings
        }
    }

    /// The pass the report screen should open onto.
    ///
    /// While Scyther is in front of the app, the last live pass — taken with nothing of Scyther's
    /// on screen — is a better answer than anything the report could measure for itself, and it is
    /// the answer the developer already has in their hand: it is what the pill counted, and what
    /// the boxes they just tapped through describe. Running a fresh pass instead is how "7 issues"
    /// came to open onto "No Issues Found": the fresh pass drops contrast, because by then the
    /// screen behind the report is Scyther's.
    ///
    /// Only the report's *first* load asks this. **Re-run** deliberately goes to
    /// ``AccessibilityAudit/auditKeyWindow()`` instead, because a developer asking for a fresh
    /// measurement should get one — with the banners explaining what a measurement taken from
    /// under Scyther's own sheet cannot include.
    ///
    /// Takes the pass the report is about to open onto, while the app is still what is on screen.
    ///
    /// Called from ``AccessibilityAuditReportPresenter/openReport()``, in the moment between the
    /// developer tapping the count pill and Scyther's sheet rising in front of the app. That moment
    /// is the only one in which a report pass can measure contrast honestly: a report is presented
    /// over the app, UIKit dims and scales everything behind it, and from then until it is
    /// dismissed the pixels in the window are Scyther's rather than the app's — which is why
    /// ``AccessibilityAudit/checksSkippedWhileCovered(from:isCovering:)`` refuses to measure them.
    /// Running the pass here is what makes "the report checks three things" true rather than
    /// aspirational.
    ///
    /// It is also the moment a pause is affordable. This pass rasterises the window and costs
    /// roughly half a second of main thread; the developer has just asked for a report and is
    /// waiting for one, where the live pass this replaces ran unasked on every navigation.
    ///
    /// The overlay is handed only the findings from the checks a live pass runs. The pill counts
    /// what live mode checks and the report counts what the report checked, and one number that
    /// silently changed meaning depending on how the developer last opened a screen would be worse
    /// than either.
    @MainActor internal func takeAccessibilityPassForReport() {
        guard canAuditThisBuild() else { return }
        guard !isScytherCoveringScreen() else { return }

        // The same pool, for the same reason, as `runAccessibilityAudit()` — and more so: this
        // pass also holds a full-window bitmap and a crop per text element.
        autoreleasepool {
            let result = runAccessibilityReportPass()
            lastUncoveredAccessibilityResult = result
            lastUncoveredAccessibilityResultTakenAt = accessibilityClock()
            let live = AccessibilityAudit.checks(for: .live, from: result.checksRun)
            accessibilityAuditView.findings = result.findings.filter { live.contains($0.check) }
        }
    }

    /// - Returns: The most recent uncovered pass, or `nil` when there has not been one — live mode
    ///   off, or on but not yet past its first debounce.
    @MainActor internal func accessibilityPassForReport() -> SeededAccessibilityPass? {
        guard isScytherCoveringScreen() else { return nil }
        guard let result = lastUncoveredAccessibilityResult,
              let takenAt = lastUncoveredAccessibilityResultTakenAt else { return nil }
        return SeededAccessibilityPass(result: result, takenAt: takenAt)
    }
}

// MARK: - Static Accessors
extension InterfaceToolkit {
    /// Whether slow animations mode is enabled.
    public static var slowAnimationsEnabled: Bool {
        get { instance.slowAnimationsEnabled }
        set { instance.slowAnimationsEnabled = newValue }
    }

    /// Whether view frames/borders are shown.
    public static var showViewFrames: Bool {
        get { instance.showsViewBorders }
        set { instance.showsViewBorders = newValue }
    }

    /// Whether view sizes are shown.
    public static var showViewSizes: Bool {
        get { instance.showsViewSizes }
        set { instance.showsViewSizes = newValue }
    }
}

// MARK: Slow Animations
extension InterfaceToolkit {
    internal func setWindowSpeed() {
        let speed: Float = slowAnimationsEnabled ? 0.1 : 1.0
        if #available(iOS 15.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    window.layer.speed = speed
                }
            }
        } else {
            for window in UIApplication.shared.windows {
                window.layer.speed = speed
            }
        }
    }
}
#endif
