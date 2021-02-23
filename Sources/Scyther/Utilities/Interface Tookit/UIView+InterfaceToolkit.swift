//
//  File.swift
//
//
//  Created by Brandon Stillitano on 20/2/21.
//

import UIKit

// MARK: - Static Data
private let UIViewPreviousBorderColorKey = "Scyther_previousBorderColor"
private let UIViewPreviousBorderWidthKey = "Scyther_previousBorderWidth"

// MARK: - Protocol
protocol InterfaceToolkitPrivate: UIView {
    var previousBorderColor: CGColor { get set }
    var previousBorderWidth: CGFloat { get set }
    var debugBorderColor: CGColor { get }
}

// MARK: - Protocol Implementation
extension UIView: InterfaceToolkitPrivate {
    var debugBorderColor: CGColor {
        return UIColor.random.cgColor
    }
    
    var previousBorderColor: CGColor {
        get {
            let color: UIColor = objc_getAssociatedObject(self, UIViewPreviousBorderColorKey) as? UIColor ?? .clear
            return color.cgColor
        }
        set {
            let color: UIColor = UIColor(cgColor: newValue)
            objc_setAssociatedObject(self,
                                     UIViewPreviousBorderColorKey,
                                     color,
                                         .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var previousBorderWidth: CGFloat {
        get {
            return objc_getAssociatedObject(self, UIViewPreviousBorderWidthKey) as? CGFloat ?? 1.0
        }
        set {
            objc_setAssociatedObject(self,
                                     UIViewPreviousBorderWidthKey,
                                     newValue,
                                         .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
        previousBorderWidth = layer.borderWidth
        previousBorderColor = layer.borderColor ?? UIColor.clear.cgColor

        /// Set new border values
        layer.borderColor = debugBorderColor
        layer.borderWidth = 1.0
    }

    func disableDebugBorders() {
        /// Set data and restore previous settings
        layer.borderColor = previousBorderColor
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
        refreshDebugBorders()
        registerForDebugBorderNotifications()
    }
}
