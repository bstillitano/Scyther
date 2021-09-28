//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import MapKit

extension CLLocationManager {
    internal static let swizzleLocationUpdates: Void = {
        let originalSelector = #selector(CLLocationManager.startUpdatingLocation)
        let swizzledSelector = #selector(swizzledStartLocation)
        swizzle(CLLocationManager.self, originalSelector, swizzledSelector)

        let originalStopSelector = #selector(CLLocationManager.stopUpdatingLocation)
        let swizzledStopSelector = #selector(swizzledStopLocation)
        swizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)

        let originalRequestSelector = #selector(CLLocationManager.requestLocation)
        let swizzledRequestSelector = #selector(swizzedRequestLocation)
        swizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)
    }()
    
    internal static let unswizzleLocationUpdates: Void = {
        let originalSelector = #selector(swizzledStartLocation)
        let swizzledSelector = #selector(CLLocationManager.startUpdatingLocation)
        swizzle(CLLocationManager.self, originalSelector, swizzledSelector)

        let originalStopSelector = #selector(swizzledStopLocation)
        let swizzledStopSelector = #selector(CLLocationManager.stopUpdatingLocation)
        swizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)

        let originalRequestSelector = #selector(swizzedRequestLocation)
        let swizzledRequestSelector = #selector(CLLocationManager.requestLocation)
        swizzle(CLLocationManager.self, originalStopSelector, swizzledStopSelector)
    }()

    @objc
    func swizzledStartLocation() {
        if let location: Location = LocationSpoofer.instance.spoofedLocation {
            LocationSpoofer.instance.startMocks(usingLocation: location)
        }
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
