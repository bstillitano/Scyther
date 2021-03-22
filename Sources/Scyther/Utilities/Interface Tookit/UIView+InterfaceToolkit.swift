//
//  File.swift
//
//
//  Created by Brandon Stillitano on 20/2/21.
//

#if !os(macOS)
import UIKit

// MARK: - Static Data
private let UIViewPreviousBorderColorKey = "Scyther_previousBorderColor"
private let UIViewPreviousBorderWidthKey = "Scyther_previousBorderWidth"

// MARK: - Protocol
protocol InterfaceToolkitPrivate: UIView {
    var previousBorderColor: String? { get set }
    var previousBorderWidth: CGFloat { get set }
    var debugBorderColor: CGColor { get }
}

// MARK: - Protocol Implementation
extension UIView: InterfaceToolkitPrivate {
    var debugBorderColor: CGColor {
        return UIColor.random.cgColor
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
    func refreshDebugBorders() {
        if InterfaceToolkit.instance.showsViewBorders {
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

// MARK: - Notifications
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

// MARK: - Swizzling
internal extension UIView {
    /// Replaces the original `layoutSubviews` implementation with the swizzled version
    static let swizzleLayout: Void = {
        /// Get original selector
        guard let originalMethod = class_getInstanceMethod(UIView.self,
                                                           #selector(layoutSubviews)) else {
            return
        }

        /// Get swizzled selector
        guard let swizzledMethod = class_getInstanceMethod(UIView.self,
                                                           #selector(swizzledLayoutSubviews)) else {
            return
        }

        /// Excahnge implementations
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    /// Swizzled implementation of layout subviews
    @objc
    private func swizzledLayoutSubviews() {
        swizzledLayoutSubviews()

        if let borderColor = layer.borderColor, previousBorderColor == nil {
            previousBorderColor = UIColor(cgColor: borderColor).hexCode()
            previousBorderWidth = layer.borderWidth
        }
        
        refreshDebugBorders()
        registerForDebugBorderNotifications()
    }
}
#endif
