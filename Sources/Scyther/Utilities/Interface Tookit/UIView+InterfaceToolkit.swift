//
//  File.swift
//
//
//  Created by Brandon Stillitano on 20/2/21.
//

import UIKit

// MARK: - Static Data
private let UIViewShowsDebugBorderKey = "Scyther_showsDebugBorder"
private let UIViewPreviousBorderColorKey = "Scyther_previousBorderColor"
private let UIViewPreviousBorderWidthKey = "Scyther_previousBorderWidth"
private let UIViewDebugBorderColorKey = "Scyther_debugBorderColor"

// MARK: - Protocol
protocol InterfaceToolkitPrivate: UIView {
    var showsDebugBorder: Bool { get set }
    var previousBorderColor: CGColor { get set }
    var previousBorderWidth: CGFloat { get set }
    var debugBorderColor: CGColor { get set }
}

// MARK: - Protocol Implementation
extension UIView: InterfaceToolkitPrivate {
    var showsDebugBorder: Bool {
        get {
            return NSNumber(nonretainedObject: objc_getAssociatedObject(self, UIViewShowsDebugBorderKey)).boolValue
        }
        set {
            objc_setAssociatedObject(self,
                                     UIViewShowsDebugBorderKey,
                                     NSNumber(value: newValue),
                                         .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
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

    var debugBorderColor: CGColor {
        get {
            let color: UIColor = objc_getAssociatedObject(self, UIViewDebugBorderColorKey) as? UIColor ?? .red
            return color.cgColor
        }
        set {
            let color: UIColor = UIColor(cgColor: newValue)
            objc_setAssociatedObject(self,
                                     UIViewDebugBorderColorKey,
                                     color,
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
        /// Check that we're not already showing debug borders, otherwise just return
        guard !self.showsDebugBorder else {
            return
        }

        /// Set data and backup current settings
        showsDebugBorder = true
        previousBorderWidth = layer.borderWidth
        previousBorderColor = layer.borderColor ?? UIColor.clear.cgColor

        /// Set new border values
        layer.borderColor = debugBorderColor
        layer.borderWidth = 1.0
    }

    func disableDebugBorders() {
        /// Check that we're currently showing debug borders, otherwise just return
        guard self.showsDebugBorder else {
            return
        }
        showsDebugBorder = false

        /// Restore previous border values
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
    @objc
    private class func swizzledInitWithFrame(frame: CGRect) -> UIView {
        let view = swizzledInitWithFrame(frame: frame)
        view.refreshDebugBorders()
        view.registerForDebugBorderNotifications()
        return view
    }

    @objc
    private class func swizzledInitWithCoder(coder: NSCoder) -> UIView {
        let view = swizzledInitWithCoder(coder: coder)
        view.refreshDebugBorders()
        view.registerForDebugBorderNotifications()
        return view
    }

    @objc
    private class func swizzledDealloc() {
        NotificationCenter.default.removeObserver(self)
    }

    class func swizzleDefaultUIView() {
        guard self == UIView.self else { return }

        let defaultInitWithFrame = class_getClassMethod(UIView.self, #selector(UIView.init(frame:)))
        let swizzledInitWithFrame = class_getClassMethod(UIView.self, #selector(UIView.swizzledInitWithFrame(frame:)))
        method_exchangeImplementations(defaultInitWithFrame!, swizzledInitWithFrame!)

        let defaultInitWithCoder = class_getClassMethod(UIView.self, #selector(UIView.init(coder:)))
        let swizzledInitWithCoder = class_getClassMethod(UIView.self, #selector(UIView.swizzledInitWithCoder(coder:)))
        method_exchangeImplementations(defaultInitWithCoder!, swizzledInitWithCoder!)
    }
}
