//
//  File.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if !os(macOS)
import NotificationCenter
import UIKit

public class InterfaceToolkit: NSObject {
    // MARK: - Static Data
    internal static var DebugBordersChangeNotification: NSNotification.Name = NSNotification.Name("DebugBordersChangeNotification")
    internal static var SlowAnimationsUserDefaultsKey: String = "Scyther_Interface_Toolkit_Slow_Animations_Enabled"
    internal static var ViewFramesUserDefaultsKey: String = "Scyther_Interface_Toolkit_View_Borders_Enabled"

    /// Private Init to Stop re-initialisation and allow singleton creation.
    override private init() { }

    /// An initialised, shared instance of the `Toggler` class.
    static let instance = InterfaceToolkit()

    // MARK: - UI Elements
    internal var gridOverlayView: GridOverlayView = GridOverlayView()
    internal var topLevelViewsWrapper: TopLevelViewsWrapper = TopLevelViewsWrapper()

    // MARK: - Data
    internal var showsViewBorders: Bool {
        get {
            UserDefaults.standard.bool(forKey: InterfaceToolkit.ViewFramesUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: InterfaceToolkit.ViewFramesUserDefaultsKey)
            NotificationCenter.default.post(name: InterfaceToolkit.DebugBordersChangeNotification,
                                            object: newValue)
        }
    }
    internal var slowAnimationsEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: InterfaceToolkit.SlowAnimationsUserDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: InterfaceToolkit.SlowAnimationsUserDefaultsKey)
            setWindowSpeed()
        }
    }

    // MARK: - Key Window Notifications
    internal func registerForNotitfcations() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(newKeyWindowNotification(notification:)),
                                               name: UIWindow.didBecomeKeyNotification,
                                               object: nil)
    }

    internal func start() {
        registerForNotitfcations()
        
        /// Delaying here to allow UIWindow time to initialise.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupTopLevelViewsWrapper()
            self?.setupGridOverlay()
            self?.setWindowSpeed()
            self?.swizzleLayout()
        }
    }

    internal func swizzleLayout() {
        UIView.swizzleLayout
    }

    private func setupTopLevelViewsWrapper() {
        guard let keyWindow: UIWindow = UIApplication.shared.keyWindow else {
            logMessage("Scyther.InterfaceToolkit failed to setup the top level views wrapper. There is no keyWindow available at UIApplication.shared.keyWindow")
            return
        }
        addTopLevelViewsWrapperToWindow(window: keyWindow)
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
}

// MARK: - Grid Overlay
extension InterfaceToolkit {
    internal func setupGridOverlay() {
        gridOverlayView.opacity = CGFloat(GridOverlay.instance.opacity)
        gridOverlayView.isHidden = true
        gridOverlayView.gridSize = GridOverlay.instance.size
        gridOverlayView.colorScheme = GridOverlay.instance.colorScheme
        topLevelViewsWrapper.addTopLevelView(topLevelView: gridOverlayView)
        showGridOverlay()
    }

    internal func showGridOverlay() {
        gridOverlayView.opacity = GridOverlay.instance.enabled ? CGFloat(GridOverlay.instance.opacity) : 0.0
        gridOverlayView.isHidden = !GridOverlay.instance.enabled
    }
}

// MARK: Slow Animations
extension InterfaceToolkit {
    internal func setWindowSpeed() {
        let speed: Float = slowAnimationsEnabled ? 0.1 : 1.0
        for window in UIApplication.shared.windows {
            window.layer.speed = speed
        }
    }
}
#endif
