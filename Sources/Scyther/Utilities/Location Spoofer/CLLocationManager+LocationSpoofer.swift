//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import MapKit

private let swizzling: (AnyClass, Selector, Selector) -> () = { forClass, originalSelector, swizzledSelector in
    if let originalMethod = class_getInstanceMethod(forClass, originalSelector),
        let swizzledMethod = class_getInstanceMethod(forClass, swizzledSelector) {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension CLLocationManager {
    static let classInit: Void = {
        let originalSelector = #selector(CLLocationManager.startUpdatingLocation)
        let swizzledSelector = #selector(swizzledStartLocation)
        swizzling(CLLocationManager.self, originalSelector, swizzledSelector)

        let originalStopSelector = #selector(CLLocationManager.stopUpdatingLocation)
        let swizzledStopSelector = #selector(swizzledStopLocation)
        swizzling(CLLocationManager.self, originalStopSelector, swizzledStopSelector)
    }()

    @objc func swizzledStartLocation() {
        print("swizzled start location")
        if !LocationSpoofer.instance.isRunning {
            LocationSpoofer.instance.startMocks(usingGPX: "Marrickville_Sydney")
        }
        LocationSpoofer.instance.delegate = self.delegate
        LocationSpoofer.instance.startUpdatingLocation()
    }

    @objc func swizzledStopLocation() {
        print("swizzled stop location")
        LocationSpoofer.instance.stopUpdatingLocation()
    }

    @objc func swizzedRequestLocation() {
        print("swizzled request location")
        LocationSpoofer.instance.requestLocation()
    }
}
