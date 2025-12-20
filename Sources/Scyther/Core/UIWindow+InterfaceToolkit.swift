//
//  File.swift
//
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

private var isSwizzled = false

extension UIWindow {
    public func swizzle() {
        guard !isSwizzled else {
            return
        }
        let sendEvent = class_getInstanceMethod(
            object_getClass(self),
            #selector(UIApplication.sendEvent(_:))
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
    @objc public func swizzledSendEvent(_ event: UIEvent) {
        TouchVisualiser.instance.handleEvent(event)
        swizzledSendEvent(event)
    }
}
