//
//  Swizzle.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation

/// Swaps the implementations of two methods at runtime.
///
/// This function uses Objective-C runtime APIs to exchange the implementations of two
/// instance methods on a given class. This technique, known as "method swizzling," allows
/// you to replace or augment existing method behavior at runtime.
///
/// - Parameters:
///   - forClass: The class containing the methods to swizzle
///   - originalSelector: The selector of the original method
///   - swizzledSelector: The selector of the replacement method
///
/// ## Example
/// ```swift
/// class MyClass: NSObject {
///     @objc dynamic func originalMethod() {
///         print("Original")
///     }
///
///     @objc dynamic func swizzledMethod() {
///         print("Swizzled")
///     }
/// }
///
/// // Swap the implementations
/// swizzle(MyClass.self, #selector(MyClass.originalMethod), #selector(MyClass.swizzledMethod))
///
/// let obj = MyClass()
/// obj.originalMethod() // Prints "Swizzled"
/// ```
///
/// - Warning: Method swizzling should be used carefully as it modifies runtime behavior.
///            Only swizzle methods marked with `@objc dynamic`.
///
/// - Note: Both methods must exist on the class for swizzling to succeed.
///         If either method is not found, no action is taken.
internal func swizzle(_ forClass: AnyClass, _ originalSelector: Selector, _ swizzledSelector: Selector) {
    if let originalMethod = class_getInstanceMethod(forClass, originalSelector),
        let swizzledMethod = class_getInstanceMethod(forClass, swizzledSelector) {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

/// Reverses a method swizzle operation, restoring original method implementations.
///
/// This function reverses the effect of method swizzling by swapping method implementations
/// back to their original state. It uses a more sophisticated approach than `swizzle` to handle
/// cases where methods may have been added or replaced.
///
/// - Parameters:
///   - forClass: The class containing the methods to unswizzle
///   - originalSelector: The selector of the original method
///   - swizzledSelector: The selector of the swizzled method
///
/// ## Example
/// ```swift
/// // After previously swizzling methods
/// unswizzle(MyClass.self, #selector(MyClass.originalMethod), #selector(MyClass.swizzledMethod))
///
/// let obj = MyClass()
/// obj.originalMethod() // Now prints "Original" again
/// ```
///
/// ## Unswizzling Process
/// 1. Attempts to add the swizzled selector with the original implementation
/// 2. If successful, replaces the original selector with the swizzled implementation
/// 3. If not successful (method already exists), exchanges implementations directly
///
/// - Warning: Unswizzling should be performed in reverse order of swizzling if multiple
///            swizzles have been applied to the same method.
///
/// - Note: Both methods must exist on the class for unswizzling to succeed.
///         If either method is not found, no action is taken.
internal func unswizzle(_ forClass: AnyClass, _ originalSelector: Selector, _ swizzledSelector: Selector) {
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
