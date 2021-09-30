//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import MapKit

extension CLLocationManager {
    internal static var isSwizzling: Bool = false
}

extension CLLocationManager {
    internal static let swizzleLocationUpdates: Void = {
        guard !isSwizzling else {
            return
        }
        
        let originalSelector = #selector(CLLocationManager.startUpdatingLocation)
        let swizzledSelector = #selector(swizzledStartLocation)
        swizzle(CLLocationManager.self, originalSelector, swizzledSelector)

        let originalStopSelector = #selector(CLLocationManager.stopUpdatingLocation)
        let swizzledStopSelector = #selector(swizzledStopLocation)
        swizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)

        let originalRequestSelector = #selector(CLLocationManager.requestLocation)
        let swizzledRequestSelector = #selector(swizzedRequestLocation)
        swizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)

        isSwizzling = true
    }()

    internal static let unswizzleLocationUpdates: Void = {
        guard isSwizzling else {
            return
        }

        let originalSelector = #selector(CLLocationManager.startUpdatingLocation)
        let swizzledSelector = #selector(swizzledStartLocation)
        unswizzle(CLLocationManager.self, originalSelector, swizzledSelector)

        let originalStopSelector = #selector(CLLocationManager.stopUpdatingLocation)
        let swizzledStopSelector = #selector(swizzledStopLocation)
        unswizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)

        let originalRequestSelector = #selector(CLLocationManager.requestLocation)
        let swizzledRequestSelector = #selector(swizzedRequestLocation)
        unswizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)

        isSwizzling = false
        LocationSpoofer.instance.delegate = self.delegate
        LocationSpoofer.instance.startUpdatingLocation()
    }()

    @objc
    func swizzledStartLocation() {
        LocationSpoofer.instance.startMocks()
        LocationSpoofer.instance.delegate = self.delegate
        LocationSpoofer.instance.startUpdatingLocation()
    }

    @objc
    func swizzledStopLocation() {
        LocationSpoofer.instance.stopUpdatingLocation()
    }

    @objc
    func swizzedRequestLocation() {
        LocationSpoofer.instance.requestLocation()
    }
}
