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

    /// Private Init to Stop re-initialisation and allow singleton creation.
    override private init() { }

    /// An initialised, shared instance of the `InterfaceToolkit` class.
    static let instance = InterfaceToolkit()

    // MARK: - UI Elements
    public var touchVisualiser: TouchVisualiser = TouchVisualiser.instance
    internal var gridOverlayView: GridOverlayView = GridOverlayView()
    internal var topLevelViewsWrapper: TopLevelViewsWrapper = TopLevelViewsWrapper()

    // MARK: - Data (nonisolated for UserDefaults access - thread-safe)
    internal nonisolated var visualiseTouches: Bool {
        get {
            UserDefaults.standard.bool(forKey: InterfaceToolkit.VisualiseTouchesUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: InterfaceToolkit.VisualiseTouchesUserDefaultsKey)
            NotificationCenter.default.post(name: InterfaceToolkit.VisualiseTouchesChangeNotification,
                                            object: newValue)
        }
    }
    internal nonisolated var showsViewBorders: Bool {
        get {
            UserDefaults.standard.bool(forKey: InterfaceToolkit.ViewFramesUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: InterfaceToolkit.ViewFramesUserDefaultsKey)
            NotificationCenter.default.post(name: InterfaceToolkit.DebugBordersChangeNotification,
                                            object: newValue)
        }
    }
    internal nonisolated var showsViewSizes: Bool {
        get {
            UserDefaults.standard.bool(forKey: InterfaceToolkit.ViewSizesUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: InterfaceToolkit.ViewSizesUserDefaultsKey)
            NotificationCenter.default.post(name: InterfaceToolkit.DebugSizesChangeNotification,
                                            object: newValue)
        }
    }
    internal nonisolated var slowAnimationsEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: InterfaceToolkit.SlowAnimationsUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: InterfaceToolkit.SlowAnimationsUserDefaultsKey)
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
    }

    internal func start() {
        registerForNotitfcations()

        /// Delaying here to allow UIWindow time to initialise.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupTopLevelViewsWrapper()
            self?.setupGridOverlay()
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
            topLevelViewsWrapper.superview?.bringSubviewToFront(topLevelViewsWrapper)
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
