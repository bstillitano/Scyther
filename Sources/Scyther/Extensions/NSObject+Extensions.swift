//
//  Runtime+Extensions.swift
//
//
//  Created by Brandon Stillitano on 2/2/21.
//

import Foundation


extension NSObject {
    /// Returns an array of all `class` objects within the running swift program that conform to a given `protocol`.
    /// - Parameter protocol: The `protocol` to be used to check for conformance
    /// - Returns: An array of `class` objects
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
    
    /// Retrieves all classes available to the running swift program
    /// - Returns: An array of `class` objects
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

        /// Deallocate classes (as you'd imagine, we will have a referece to over 3000 class objects so need to deallocate)
        allClasses.deallocate()

        return classes
    }
}
