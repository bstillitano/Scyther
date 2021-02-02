//
//  Runtime+Extensions.swift
//
//
//  Created by Brandon Stillitano on 2/2/21.
//

import Foundation


extension NSObject {
    public func classesConformingToProtocol(_ protocol: Protocol) -> [AnyClass] {
        let classes = objc1_getClassList()
        var conformingClasses: [AnyClass] = []

        for `class` in classes {
            if class_conformsToProtocol(`class`, `protocol`) {
                conformingClasses.append(`class`)
            }
        }
        return conformingClasses
    }

    private func objc1_getClassList() -> [AnyClass] {
        let expectedClassCount = objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(expectedClassCount))

        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        objc_getClassList(autoreleasingAllClasses, Int32(expectedClassCount))

        let actualClassCount: Int32 = objc_getClassList(autoreleasingAllClasses, expectedClassCount)

        var classes = [AnyClass]()
        for index in 0 ..< actualClassCount {
            if let currentClass: AnyClass = allClasses[Int(index)] {
                classes.append(currentClass)
            }
        }

        allClasses.deallocate()

        return classes
    }
}
