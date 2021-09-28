//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation

internal let swizzle: (AnyClass, Selector, Selector) -> () = { forClass, originalSelector, swizzledSelector in
    if let originalMethod = class_getInstanceMethod(forClass, originalSelector),
        let swizzledMethod = class_getInstanceMethod(forClass, swizzledSelector) {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

internal let unswizzle: (AnyClass, Selector, Selector) -> () = { forClass, originalSelector, swizzledSelector in
    guard let originalMethod = class_getInstanceMethod(forClass, originalSelector),
        let swizzledMethod = class_getInstanceMethod(forClass, swizzledSelector) else {
        return
    }
    if class_addMethod(forClass, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(swizzledMethod)) {
        class_replaceMethod(forClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
    } else {
        method_exchangeImplementations(swizzledMethod, originalMethod)
    }
}
