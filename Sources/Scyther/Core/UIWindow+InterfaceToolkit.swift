//
//  UIWindow+InterfaceToolkit.swift
//
//
//  Created by Brandon Stillitano on 26/9/21.
//

#if !os(macOS)
import UIKit

/// Tracks whether the UIWindow's sendEvent method has been swizzled.
nonisolated(unsafe) private var isSwizzled = false

/// Extension providing touch event interception for the touch visualiser.
///
/// This extension swizzles `UIWindow.sendEvent(_:)` to intercept touch events
/// and forward them to the ``TouchVisualiser`` for visualization.
///
/// - Important: This uses method swizzling and is intended for development use only.
extension UIWindow {
    /// Swizzles the sendEvent method to enable touch visualization.
    ///
    /// This method exchanges the implementation of `sendEvent(_:)` with a custom
    /// version that forwards events to ``TouchVisualiser`` before processing.
    /// The swizzling only occurs once per app lifecycle.
    public func swizzle() {
        guard !isSwizzled else {
            return
        }
        let sendEvent = class_getInstanceMethod(
            object_getClass(self),
            #selector(UIWindow.sendEvent(_:))
        )
        let swizzledSendEvent = class_getInstanceMethod(
            object_getClass(self),
            #selector(UIWindow.swizzledSendEvent(_:))
        )
        method_exchangeImplementations(sendEvent!, swizzledSendEvent!)

        isSwizzled = true
        registerForVisualiseTouchesNotifications()
    }
}

// MARK: - Swizzling
extension UIWindow {
    /// Swizzled implementation of sendEvent that forwards events to TouchVisualiser.
    ///
    /// - Parameter event: The UIEvent to process.
    @objc public func swizzledSendEvent(_ event: UIEvent) {
        // Check static flag first to avoid MainActor hop when disabled
        // Handle synchronously on main thread to ensure touch events are processed in time
        if TouchVisualiser.isEnabled && event.type == .touches {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    TouchVisualiser.instance.handleEvent(event)
                }
            } else {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        TouchVisualiser.instance.handleEvent(event)
                    }
                }
            }
        }
        swizzledSendEvent(event)
    }
}
#endif
