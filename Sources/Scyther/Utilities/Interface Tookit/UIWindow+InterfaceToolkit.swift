//
//  File.swift
//
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

fileprivate var isSwizzled = false

@available(iOS 8.0, *)
extension UIWindow {

    public func swizzle() {
        guard isSwizzled == false else {
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
    }
}

// MARK: - Swizzle
extension UIWindow {
    @objc public func swizzledSendEvent(_ event: UIEvent) {
        TouchVisualiser.sharedInstance.handleEvent(event)
        swizzledSendEvent(event)
    }
}
