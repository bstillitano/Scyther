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

    /// Returns whether location methods are currently swizzled
    public static var isLocationSwizzled: Bool {
        return isSwizzling
    }
}

extension CLLocationManager {
    internal static func swizzleLocationUpdates() {
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
        let swizzledRequestSelector = #selector(swizzledRequestLocation)
        swizzle(CLLocationManager.self, originalRequestSelector, swizzledRequestSelector)

        isSwizzling = true
    }

    internal static func unswizzleLocationUpdates() {
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
        let swizzledRequestSelector = #selector(swizzledRequestLocation)
        unswizzle(CLLocationManager.self, originalRequestSelector, swizzledRequestSelector)

        isSwizzling = false
    }

    @objc
    func swizzledStartLocation() {
        guard LocationSpoofer.instance.spoofingEnabled else {
            // Call original implementation (now at swizzled selector due to swap)
            swizzledStartLocation()
            return
        }
        LocationSpoofer.instance.delegate = self.delegate
        LocationSpoofer.instance.startMocks()
        LocationSpoofer.instance.startUpdatingLocation()
    }

    @objc
    func swizzledStopLocation() {
        guard LocationSpoofer.instance.spoofingEnabled else {
            swizzledStopLocation()
            return
        }
        LocationSpoofer.instance.stopUpdatingLocation()
    }

    @objc
    func swizzledRequestLocation() {
        guard LocationSpoofer.instance.spoofingEnabled else {
            // Call original implementation (now at swizzled selector due to swap)
            swizzledRequestLocation()
            return
        }
        LocationSpoofer.instance.delegate = self.delegate
        LocationSpoofer.instance.startMocks()
        LocationSpoofer.instance.requestLocation()
    }
}
