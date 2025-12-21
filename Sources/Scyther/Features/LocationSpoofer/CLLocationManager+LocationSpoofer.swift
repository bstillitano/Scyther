//
//  CLLocationManager+LocationSpoofer.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
@preconcurrency import MapKit

/// Extension providing method swizzling for location spoofing.
///
/// This extension intercepts Core Location method calls to provide spoofed coordinates
/// instead of real GPS data when location spoofing is enabled.
extension CLLocationManager {
    /// Flag indicating whether location methods are currently swizzled.
    nonisolated(unsafe) internal static var isSwizzling: Bool = false

    /// Returns whether location methods are currently swizzled.
    ///
    /// This property can be checked to determine if location spoofing is active.
    ///
    /// - Returns: `true` if methods are swizzled, `false` otherwise.
    public static var isLocationSwizzled: Bool {
        return isSwizzling
    }
}

/// Extension containing swizzling implementation methods.
extension CLLocationManager {
    /// Swizzles location update methods to enable spoofing.
    ///
    /// This method exchanges the implementations of Core Location methods with
    /// custom implementations that provide spoofed coordinates when enabled.
    ///
    /// - Note: This is called automatically by `LocationSpoofer.start()`.
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

    /// Unswizzles location update methods to restore normal operation.
    ///
    /// This method restores the original Core Location method implementations,
    /// disabling location spoofing.
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

    /// Helper to safely get spoofing state from any thread.
    /// Now simple since spoofingEnabled is nonisolated (UserDefaults is thread-safe).
    private static func getSpoofingEnabled() -> Bool {
        return LocationSpoofer.instance.spoofingEnabled
    }

    /// Swizzled implementation of `startUpdatingLocation()`.
    ///
    /// If spoofing is enabled, starts providing fake locations. Otherwise,
    /// calls the original implementation.
    /// - Note: CLLocationManager should only be used from the main thread.
    @objc
    func swizzledStartLocation() {
        guard Self.getSpoofingEnabled() else {
            // Call original implementation (now at swizzled selector due to swap)
            swizzledStartLocation()
            return
        }
        // Capture delegate before dispatch to avoid capturing self
        let capturedDelegate = self.delegate
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                LocationSpoofer.instance.delegate = capturedDelegate
                LocationSpoofer.instance.startMocks()
                LocationSpoofer.instance.startUpdatingLocation()
            }
        } else {
            DispatchQueue.main.async {
                LocationSpoofer.instance.delegate = capturedDelegate
                LocationSpoofer.instance.startMocks()
                LocationSpoofer.instance.startUpdatingLocation()
            }
        }
    }

    /// Swizzled implementation of `stopUpdatingLocation()`.
    ///
    /// If spoofing is enabled, stops providing fake locations. Otherwise,
    /// calls the original implementation.
    /// - Note: CLLocationManager should only be used from the main thread.
    @objc
    func swizzledStopLocation() {
        guard Self.getSpoofingEnabled() else {
            swizzledStopLocation()
            return
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                LocationSpoofer.instance.stopUpdatingLocation()
            }
        } else {
            DispatchQueue.main.async {
                LocationSpoofer.instance.stopUpdatingLocation()
            }
        }
    }

    /// Swizzled implementation of `requestLocation()`.
    ///
    /// If spoofing is enabled, provides a single fake location. Otherwise,
    /// calls the original implementation.
    /// - Note: CLLocationManager should only be used from the main thread.
    @objc
    func swizzledRequestLocation() {
        guard Self.getSpoofingEnabled() else {
            // Call original implementation (now at swizzled selector due to swap)
            swizzledRequestLocation()
            return
        }
        // Capture delegate before dispatch to avoid capturing self
        let capturedDelegate = self.delegate
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                LocationSpoofer.instance.delegate = capturedDelegate
                LocationSpoofer.instance.startMocks()
                LocationSpoofer.instance.requestLocation()
            }
        } else {
            DispatchQueue.main.async {
                LocationSpoofer.instance.delegate = capturedDelegate
                LocationSpoofer.instance.startMocks()
                LocationSpoofer.instance.requestLocation()
            }
        }
    }
}
