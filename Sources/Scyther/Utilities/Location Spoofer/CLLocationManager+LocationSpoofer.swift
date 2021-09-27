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
    }()

    @objc
    func swizzledStartLocation() {
        if !LocationSpoofer.instance.isRunning {
            LocationSpoofer.instance.startMocks(usingGPX: "Marrickville_Sydney")
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
