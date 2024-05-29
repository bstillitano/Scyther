//
//  File.swift
//
//
//  Created by Brandon Stillitano on 20/2/21.
//

#if !os(macOS)
import UIKit

// MARK: - Static Data
private let UIViewPreviousMasksToBoundsKey = "Scyther_previousMasksToBounds"
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
        if InterfaceToolkit.instance.showsViewSizes {
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
        
        /// Build and add sublayer
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(x: 0, y: -10, width: max(frame.width, 200), height: 60)
        textLayer.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
        textLayer.fontSize = UIFont.smallSystemFontSize
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = true
        textLayer.truncationMode = .none
        textLayer.string = "x: \(frame.minX.rounded()), y: \(frame.minY.rounded()), w: \(frame.width.rounded()), h: \(frame.height.rounded())"
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
internal extension UIView {
    /// Replaces the original `layoutSubviews` implementation with the swizzled version
    static let swizzleLayout: Void = {
        let originalSelector = #selector(layoutSubviews)
        let swizzledSelector = #selector(swizzledLayoutSubviews)
        swizzle(UIView.self, originalSelector, swizzledSelector)
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
        
        refreshDebugViewSizes()
        registerForDebugViewSizeNotifications()
    }
}
#endif
