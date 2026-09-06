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
        let enabled = AccessibilityAudit.instance.liveEnabled
        accessibilityAuditView.isHidden = !enabled
        if enabled {
            scheduleAccessibilityReaudit()
        } else {
            pendingAccessibilityAudit?.cancel()
            pendingAccessibilityAudit = nil
            accessibilityAuditView.findings = []
        }
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
        guard AccessibilityAudit.instance.liveEnabled else { return }

        pendingAccessibilityAudit?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.runAccessibilityAudit()
        }
        pendingAccessibilityAudit = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.AccessibilityAuditDebounceInterval, execute: workItem)
    }

    /// Runs the audit and hands its findings to the overlay.
    ///
    /// Only ``scheduleAccessibilityReaudit()`` calls this — nothing audits the window
    /// immediately, even when live mode is first switched on, so that the very first audit
    /// after enabling live mode gets the same debounce as every subsequent one and does not
    /// race a layout pass that has not finished yet.
    @MainActor private func runAccessibilityAudit() {
        pendingAccessibilityAudit = nil
        accessibilityAuditView.findings = AccessibilityAudit.instance.auditKeyWindow().findings
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
