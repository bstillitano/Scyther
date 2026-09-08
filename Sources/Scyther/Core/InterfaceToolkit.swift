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

    /// The longest a pending pass may be deferred by fresh triggers before it is left to run.
    ///
    /// A trigger arriving one debounce after the last one cancels the pending pass at about the
    /// instant it was due, over and over. That is not a corner case now that the trigger is the
    /// app laying out — see ``appViewDidLayout(_:)``: a screen with a spinner, a video layer, an
    /// auto-advancing carousel or an animation that never settles lays out on every frame for as
    /// long as it is on screen, so without a cap the boxes would never update on it at all — no
    /// spinner, no banner, and no way to force a pass short of opening the report.
    ///
    /// Two seconds, measured from the *first* trigger of a run rather than the last, so a genuine
    /// burst still coalesces into one pass while an endless stream cannot starve it. Past the floor
    /// the pending pass is left alone rather than replaced: a pass of a screen two seconds stale is
    /// worth incomparably more than a pass that never happens.
    ///
    /// It is the one exception to "a pass lands only once the screen stops moving", and it is not
    /// free: an unbroken scroll longer than the floor plus a debounce takes a live pass — about
    /// 121ms of main thread — while it is still moving, roughly every two and a half seconds. That
    /// is the price of the overlay ever being right on a screen that never settles, and it is paid
    /// only in live mode, which is off unless a developer switched it on.
    nonisolated internal static let AccessibilityAuditMaximumDeferral: TimeInterval = 2

    /// Private Init to Stop re-initialisation and allow singleton creation.
    override private init() { }

    /// An initialised, shared instance of the `InterfaceToolkit` class.
    static let instance = InterfaceToolkit()

    // MARK: - UI Elements
    public var touchVisualiser: TouchVisualiser = TouchVisualiser.instance
    internal var gridOverlayView: GridOverlayView = GridOverlayView()
    internal var layoutGuidesView: LayoutGuidesView = LayoutGuidesView()
    internal var layoutRulerView: LayoutRulerOverlayView = LayoutRulerOverlayView()
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

    /// Whether a layout this turn has already been counted, so a single layout pass — which lays
    /// out every view that needs it, hundreds of them while a scroll is tracking — costs one
    /// schedule rather than hundreds.
    ///
    /// Coalescing here rather than leaning on the debounce alone is about allocation, not about
    /// correctness: the debounce would collapse them all into one pass either way, but each call to
    /// ``scheduleAccessibilityReaudit()`` cancels a `DispatchWorkItem`, allocates another and arms a
    /// timer, and doing that per view per frame is work the developer can feel. The pass still lands
    /// one debounce after the *last* layout, because the last layout of the last frame still
    /// restarts it.
    ///
    /// Cleared one run-loop turn later, which is the definition of "this turn" that costs nothing to
    /// evaluate. Readable so a test can tell a coalesced burst from a suppressed trigger.
    internal private(set) var hasNotedALayoutThisTurn = false

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
    /// persisted — the exact combination that guard names as the hole — watched every view in the
    /// app lay out for the life of the process (see ``appViewDidLayout(_:)``), scheduled a
    /// `DispatchWorkItem` on every frame of every scroll, and left a full-screen overlay consulted
    /// on every touch, all to feed a function whose only possible answer was an empty result.
    /// Nothing may be installed, observed or scheduled in a build where the audit cannot run.
    ///
    /// Injected because `AppEnvironment.isTestCase` is unconditionally `true` under XCTest and
    /// `isAppStore` unconditionally `false`, so neither branch could otherwise be reached by a test.
    internal var canAuditThisBuild: @MainActor () -> Bool = {
        AccessibilityAudit.canAuditKeyWindow(isTestCase: AppEnvironment.isTestCase,
                                             isAppStore: AppEnvironment.isAppStore)
    }

    /// Whether the app laying out currently triggers a re-audit.
    ///
    /// A `nonisolated(unsafe) static var` rather than a question asked of the singleton because
    /// ``appViewDidLayout(_:)`` — the swizzled `layoutSubviews` that reads it — runs for every view
    /// in the app, hundreds of times a frame while a scroll is tracking. It has to be able to rule
    /// itself out in a single load: the guards in ``scheduleAccessibilityReaudit()`` are a
    /// `ProcessInfo.environment` dictionary build (``AppEnvironment/isTestCase``), a
    /// `Bundle.main.appStoreReceiptURL` read (``AppEnvironment/isTestFlight``) and a `UserDefaults`
    /// lookup, none of which belongs on a per-view-per-frame path.
    ///
    /// `(unsafe)` for the same reason every other `nonisolated(unsafe)` flag in Scyther is: it is
    /// only ever written from ``showAccessibilityAudit()`` and only ever read from `layoutSubviews`,
    /// both of which are main-thread by construction, and the compiler cannot see that a swizzled
    /// Objective-C entry point is main-actor isolated.
    ///
    /// Readable so a test can assert that a build the audit may not run on, or a session with live
    /// mode off, is not watching anything.
    nonisolated(unsafe) internal static var isObservingAppLayout = false

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
            self?.setupLayoutGuides()
            self?.setupFPSCounter()
            self?.setupAccessibilityAudit()
            self?.setupLayoutRuler()
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
        layoutRulerView.refreshForCoverageChange()
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

// MARK: - Layout Guides
extension InterfaceToolkit {
    /// Installs the guides overlay, hidden, and brings it to its current setting.
    @MainActor internal func setupLayoutGuides() {
        layoutGuidesView.isHidden = true
        topLevelViewsWrapper.addTopLevelView(topLevelView: layoutGuidesView)
        showLayoutGuides()
    }

    /// Applies ``LayoutGuides/enabled`` to the overlay.
    @MainActor internal func showLayoutGuides() {
        layoutGuidesView.isHidden = !LayoutGuides.instance.enabled
    }
}

// MARK: - Layout Ruler
extension InterfaceToolkit {
    /// Installs the ruler's overlay, inactive, and wires the two things it reports back.
    ///
    /// Added after ``setupAccessibilityAudit()`` inside ``start()``, so it is the frontmost of the
    /// wrapper's children: while the ruler is active it is the one overlay that takes touches, and
    /// a sibling added later would sit over it and take them instead.
    ///
    /// ``LayoutRulerOverlayView/onDone`` and ``LayoutRulerOverlayView/onSnapModeChanged`` are wired
    /// here rather than the overlay reaching for ``LayoutRuler`` itself, matching
    /// ``AccessibilityAuditOverlayView/onOpenReport``: the overlay knows only that its button was
    /// tapped, and this is the one place that knows what that means.
    @MainActor internal func setupLayoutRuler() {
        layoutRulerView.isHidden = true
        layoutRulerView.onDone = {
            LayoutRuler.instance.isActive = false
        }
        layoutRulerView.onSnapModeChanged = { snaps in
            LayoutRuler.instance.snaps = snaps
        }
        topLevelViewsWrapper.addTopLevelView(topLevelView: layoutRulerView)
        showLayoutRuler()
    }

    /// Applies ``LayoutRuler/isActive`` and ``LayoutRuler/snaps`` to the overlay, mirroring
    /// ``showLayoutGuides()``.
    ///
    /// Both in one call because activation is the moment the mode matters: the picker has to show
    /// the mode the next drag will actually use, and the two are only ever read together.
    @MainActor internal func showLayoutRuler() {
        layoutRulerView.snapsToEdges = LayoutRuler.instance.snaps
        layoutRulerView.setActive(LayoutRuler.instance.isActive)
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
    ///
    /// It is also the only place ``isObservingAppLayout`` is written, which is what makes the app
    /// laying out cost one static load rather than a `ProcessInfo.environment` build and a
    /// `UserDefaults` lookup in every app that has never switched this on.
    @MainActor internal func showAccessibilityAudit() {
        let enabled = canAuditThisBuild() && AccessibilityAudit.instance.liveEnabled
        accessibilityAuditView.isHidden = !enabled
        Self.isObservingAppLayout = enabled
        if enabled {
            scheduleAccessibilityReaudit()
        } else {
            hasNotedALayoutThisTurn = false
            pendingAccessibilityAudit?.cancel()
            pendingAccessibilityAudit = nil
            pendingAccessibilityAuditDeadline = nil
            accessibilityAuditFirstScheduledAt = nil
            lastUncoveredAccessibilityResult = nil
            lastUncoveredAccessibilityResultTakenAt = nil
            accessibilityAuditView.findings = []
        }
    }

    /// Schedules a re-audit because the app just laid something out.
    ///
    /// ## Why layout, and not the controller chain
    ///
    /// This used to poll, twice a second, for a change in which view controllers were showing. That
    /// question has an honest answer in a UIKit app and almost none in a SwiftUI one: a `TabView`
    /// switch, a `NavigationStack` push and a `List` scroll all happen inside a single
    /// `UIHostingController`, so the chain never moved and the overlay drew one pass at launch and
    /// then described a screen that had gone. Measured on a simulator: one pass, at launch, and not
    /// another for the rest of the session however much the app was navigated.
    ///
    /// Layout is the signal that actually moves. Nothing changes what is on screen without laying
    /// something out — a push lays out the incoming view, `addSubview` marks its new superview as
    /// needing layout, a scroll lays out the scroll view on every frame it tracks, a reload lays out
    /// the cells that changed. Scyther already swizzles `UIView.layoutSubviews` process-wide for the
    /// view-borders and view-sizes overlays, so this costs no new hook: see
    /// `UIView.swizzledLayoutSubviews()`.
    ///
    /// ## Why it cannot feed itself
    ///
    /// A pass draws boxes, and drawing is layout, so the obvious failure is a pass that schedules
    /// the next one for ever. Two independent things stop it, and either alone would be enough.
    ///
    /// Everything the live overlay draws — the boxes, the count pill, the flash layer — lives inside
    /// ``topLevelViewsWrapper``, and a layout inside that wrapper is refused here. So is every other
    /// overlay Scyther keeps on screen, which matters as much: ``FPSCounterView`` lays its label
    /// out again on every frame it samples, and without this it alone would have kept a pass
    /// permanently pending.
    ///
    /// And a pass that finds what the last one found changes nothing on screen at all —
    /// ``AccessibilityAuditOverlayView/findings`` drops it before any redraw, see
    /// ``AccessibilityAuditOverlayView/describeTheSameElements(_:_:)`` — so even without the wrapper
    /// rule the loop would have to terminate on the second pass rather than run away.
    ///
    /// ## What it still misses
    ///
    /// Content that changes with no `UIView` laying out: a screen whose entire body is drawn by
    /// SwiftUI into one backing view that never re-lays out, or a `CALayer` animating on its own.
    /// Those keep the last pass's boxes until something else moves, and the escape is the same as
    /// for a pass gone stale for any other reason — tapping the pill takes a fresh one.
    ///
    /// - Parameter view: The view that just laid out.
    @MainActor internal static func appViewDidLayout(_ view: UIView) {
        guard isObservingAppLayout else { return }
        instance.appViewDidLayout(view)
    }

    /// The instance half of ``appViewDidLayout(_:)``, split out so the static entry point stays a
    /// single load in the case that matters — live mode off, which is every app that has not asked
    /// for this.
    ///
    /// - Parameter view: The view that just laid out.
    @MainActor internal func appViewDidLayout(_ view: UIView) {
        guard !hasNotedALayoutThisTurn else { return }
        guard !view.isDescendant(of: topLevelViewsWrapper) else { return }

        hasNotedALayoutThisTurn = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.hasNotedALayoutThisTurn = false
            }
        }
        scheduleAccessibilityReaudit()
    }

    /// Forgets that a layout has already been counted this turn.
    ///
    /// The reset production relies on is the `DispatchQueue.main.async` block above, one run-loop
    /// turn out. A synchronous test cannot wait for that without turning every assertion about the
    /// trigger into an asynchronous one, so this says "and now it is the next frame" in one line.
    /// Nothing in Scyther calls it.
    @MainActor internal func forgetTheLayoutNotedThisTurn() {
        hasNotedALayoutThisTurn = false
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
    ///
    /// Every trigger restarts the debounce, which is what makes a 121ms pass affordable: the pass
    /// lands once the screen stops moving rather than while it is moving. The one exception is
    /// ``AccessibilityAuditMaximumDeferral``, below — a stream of triggers that never stops cannot
    /// defer a pass for ever.
    @MainActor internal func scheduleAccessibilityReaudit() {
        guard canAuditThisBuild(), AccessibilityAudit.instance.liveEnabled else { return }

        let now = accessibilityClock()
        // Past the floor, the pass that has been waiting is left exactly where it is. Cancelling it
        // again is what would let a screen that never stops laying out defer it indefinitely.
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
