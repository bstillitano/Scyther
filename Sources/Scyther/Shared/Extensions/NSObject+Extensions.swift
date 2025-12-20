//
//  NSObject+Extensions.swift
//
//
//  Created by Brandon Stillitano on 2/2/21.
//

import Foundation

/// Provides runtime introspection extensions for NSObject.
///
/// This extension adds utility methods for discovering and working with classes at runtime,
/// particularly for finding classes that conform to specific protocols using Objective-C runtime APIs.
extension NSObject {
    /// Returns an array of all class objects within the running Swift program that conform to a given protocol.
    ///
    /// This method uses the Objective-C runtime to introspect all loaded classes and filters
    /// them based on protocol conformance. This is useful for plugin architectures, dependency
    /// injection, or discovering implementations at runtime.
    ///
    /// - Parameter protocol: The protocol to check for conformance
    ///
    /// - Returns: An array of class objects that conform to the specified protocol
    ///
    /// ## Example
    /// ```swift
    /// // Define a protocol
    /// @objc protocol ConfigurableFeature {
    ///     static func configure()
    /// }
    ///
    /// // Find all classes that conform to it
    /// let object = NSObject()
    /// let configurableClasses = object.classesConformingToProtocol(ConfigurableFeature.self)
    ///
    /// // Configure all conforming classes
    /// for featureClass in configurableClasses {
    ///     (featureClass as? ConfigurableFeature.Type)?.configure()
    /// }
    /// ```
    ///
    /// - Note: The protocol must be marked with `@objc` for runtime introspection to work.
    ///
    /// - Warning: This method retrieves all classes loaded in the runtime (typically 3000+),
    ///            so use it judiciously. Consider caching results if called frequently.
    public func classesConformingToProtocol(_ protocol: Protocol) -> [AnyClass] {
        /// Get all classes
        let classes = objc1_getClassList()
        var conformingClasses: [AnyClass] = []

        /// Check class conformance
        for `class` in classes {
            if class_conformsToProtocol(`class`, `protocol`) {
                conformingClasses.append(`class`)
            }
        }
        return conformingClasses
    }

    /// Retrieves all classes available to the running Swift program.
    ///
    /// This private helper method uses the Objective-C runtime to enumerate all loaded classes.
    /// It handles memory allocation and deallocation for the class list and returns them as an array.
    ///
    /// - Returns: An array of all class objects currently loaded in the runtime
    ///
    /// - Note: This method is called internally by `classesConformingToProtocol(_:)` and properly
    ///         manages memory by deallocating the class list after enumeration.
    ///
    /// - Warning: The returned array typically contains 3000+ class objects depending on
    ///            the frameworks and libraries loaded by your application.
    private func objc1_getClassList() -> [AnyClass] {
        /// Get all classes
        let expectedClassCount = objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(expectedClassCount))

        /// Get all classes that are configured to auto-release
        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        objc_getClassList(autoreleasingAllClasses, Int32(expectedClassCount))

        /// Combine class lists
        let actualClassCount: Int32 = objc_getClassList(autoreleasingAllClasses, expectedClassCount)

        /// Enumerate classes and add to final list
        var classes: [AnyClass] = []
        for index in 0 ..< actualClassCount {
            if let currentClass: AnyClass = allClasses[Int(index)] {
                classes.append(currentClass)
            }
        }

        /// Deallocate classes (as you'd imagine, we will have a reference to over 3000 class objects so need to deallocate)
        allClasses.deallocate()

        return classes
    }
}
