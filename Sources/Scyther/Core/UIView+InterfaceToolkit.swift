//
//  UIView+InterfaceToolkit.swift
//
//
//  Created by Brandon Stillitano on 20/2/21.
//

#if !os(macOS)
import UIKit

/// Extension providing debug border and size visualization capabilities for UIView.
///
/// This file contains internal extensions to UIView that enable the view debugging
/// features in Scyther's Interface Toolkit. Features include:
/// - Debug borders: Adds colored borders to all views for layout debugging
/// - Debug sizes: Shows view dimensions as text labels
///
/// These features are controlled via ``InterfaceToolkit`` and are not intended
/// for direct use.

// MARK: - Static Data
private let UIViewPreviousMasksToBoundsKey = "Scyther_previousMasksToBounds"
private let UIViewPreviousBorderColorKey = "Scyther_previousBorderColor"
private let UIViewPreviousBorderWidthKey = "Scyther_previousBorderWidth"

// MARK: - Protocol

/// Internal protocol for managing debug visualization state on UIViews.
protocol InterfaceToolkitPrivate: UIView {
    /// The previously set border color, stored as a hex string.
    var previousBorderColor: String? { get set }
    /// The previously set border width.
    var previousBorderWidth: CGFloat { get set }
    /// A randomly generated color for this view's debug border.
    var debugBorderColor: CGColor { get }
}

// MARK: - Protocol Implementation
extension UIView: InterfaceToolkitPrivate {
    var debugBorderColor: CGColor {
        return UIColor.random.cgColor
    }

    var previousMasksToBounds: Bool? {
        get {
            let value: Bool? = objc_getAssociatedObject(self, UIViewPreviousMasksToBoundsKey) as? Bool
            return value
        }
        set {
            objc_setAssociatedObject(self, UIViewPreviousMasksToBoundsKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    
    var previousBorderColor: String? {
        get {
            let hexCode: String? = objc_getAssociatedObject(self, UIViewPreviousBorderColorKey) as? String
            return hexCode
        }
        set {
            objc_setAssociatedObject(self, UIViewPreviousBorderColorKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var previousBorderWidth: CGFloat {
        get {
            return objc_getAssociatedObject(self, UIViewPreviousBorderWidthKey) as? CGFloat ?? 0.0
        }
        set {
            objc_setAssociatedObject(self, UIViewPreviousBorderWidthKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

// MARK: - Show/Hide View Borders
internal extension UIView {
    /// Reads directly from UserDefaults to avoid MainActor hop
    private static var showsViewBordersFromDefaults: Bool {
        UserDefaults.standard.bool(forKey: InterfaceToolkit.ViewFramesUserDefaultsKey)
    }

    /// Reads directly from UserDefaults to avoid MainActor hop
    private static var showsViewSizesFromDefaults: Bool {
        UserDefaults.standard.bool(forKey: InterfaceToolkit.ViewSizesUserDefaultsKey)
    }

    func refreshDebugBorders() {
        if Self.showsViewBordersFromDefaults {
            enableDebugBorders()
        } else {
            disableDebugBorders()
        }
    }

    func enableDebugBorders() {
        /// Set data and backup current settings
        if let borderColor = layer.borderColor {
            previousBorderWidth = layer.borderWidth
            previousBorderColor = UIColor(cgColor: borderColor).hexCode()
        }

        /// Set new border values
        layer.borderColor = debugBorderColor
        layer.borderWidth = 1.0
    }

    func disableDebugBorders() {
        /// Set data and restore previous settings
        layer.borderColor = UIColor(hex: previousBorderColor)?.cgColor
        layer.borderWidth = previousBorderWidth
    }
}


// MARK: - Debug Border Notifications
internal extension UIView {
    func registerForDebugBorderNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(debugBordersChanged),
                                               name: InterfaceToolkit.DebugBordersChangeNotification,
                                               object: nil)
    }

    @objc
    func debugBordersChanged() {
        refreshDebugBorders()
    }
}

// MARK: - Show/Hide View Frames
internal extension UIView {
    func refreshDebugViewSizes() {
        if Self.showsViewSizesFromDefaults {
            enableDebugViewSizes()
        } else {
            disableDebugViewSizes()
        }
    }

    func enableDebugViewSizes() {
        /// Check that we haven't already added a sublayer
        guard layer.sublayers?.contains(where: {$0.name == "Scyther_Debug_Frame_Label" }) != true else { return }
        
        /// Set data and backup current settings
        previousMasksToBounds = layer.masksToBounds
        
        /// Build and add sublayer.
        /// Setting max width of sublayer to 200 here as an arbitrary number that seems to sort of be the happy middle ground between going off the screen and views being too narrow to meaningfully display anything.
        /// Pretty crappy still, needs to be improved.
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(x: 0, y: -12, width: max(frame.width, 200), height: 60)
        textLayer.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
        textLayer.fontSize = UIFont.smallSystemFontSize
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = true
        textLayer.truncationMode = .none
        textLayer.string = "w:\(frame.width.rounded()), h:\(frame.height.rounded())"
        textLayer.foregroundColor = layer.borderColor ?? UIColor.random.cgColor
        textLayer.name = "Scyther_Debug_Frame_Label"
        layer.masksToBounds = false
        layer.addSublayer(textLayer)
    }

    func disableDebugViewSizes() {
        layer.sublayers?.removeAll(where: { $0.name == "Scyther_Debug_Frame_Label" })
        layer.masksToBounds = previousMasksToBounds ?? true
    }
}


// MARK: - Debug View Size Notifications
internal extension UIView {
    func registerForDebugViewSizeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(debugViewSizesChanged),
                                               name: InterfaceToolkit.DebugSizesChangeNotification,
                                               object: nil)
    }

    @objc
    func debugViewSizesChanged() {
        refreshDebugViewSizes()
    }
}

// MARK: - Visualise Touches Notifications
internal extension UIView {
    func registerForVisualiseTouchesNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(visualiseTouchesChanged),
                                               name: InterfaceToolkit.VisualiseTouchesChangeNotification,
                                               object: nil)
    }

    @objc
    func visualiseTouchesChanged() {
        if InterfaceToolkit.instance.visualiseTouches {
            TouchVisualiser.instance.start()
        } else {
            TouchVisualiser.instance.stop()
        }
    }
}

// MARK: - Swizzling
nonisolated(unsafe) private var hasRegisteredForDebugNotificationsKey: UInt8 = 0

internal extension UIView {
    /// Replaces the original `layoutSubviews` implementation with the swizzled version
    static let swizzleLayout: Void = {
        let originalSelector = #selector(layoutSubviews)
        let swizzledSelector = #selector(swizzledLayoutSubviews)
        swizzle(UIView.self, originalSelector, swizzledSelector)
    }()

    private var hasRegisteredForDebugNotifications: Bool {
        get { objc_getAssociatedObject(self, &hasRegisteredForDebugNotificationsKey) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &hasRegisteredForDebugNotificationsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Swizzled implementation of layout subviews
    @objc
    private func swizzledLayoutSubviews() {
        swizzledLayoutSubviews()

        // Only register for notifications once per view
        guard !hasRegisteredForDebugNotifications else { return }
        hasRegisteredForDebugNotifications = true

        if let borderColor = layer.borderColor, previousBorderColor == nil {
            previousBorderColor = UIColor(cgColor: borderColor).hexCode()
            previousBorderWidth = layer.borderWidth
        }

        refreshDebugBorders()
        registerForDebugBorderNotifications()

        refreshDebugViewSizes()
        registerForDebugViewSizeNotifications()
    }
}
#endif
