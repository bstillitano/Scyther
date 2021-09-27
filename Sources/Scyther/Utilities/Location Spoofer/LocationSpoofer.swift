//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import CoreLocation

class LocationSpoofer: NSObject {
    // MARK: - Notifications
    internal static var LocationSpooferSimulatedLatitudeDefaultsKey: String = "Scyther_Location_Spoofer_Simulated_Latitude"
    internal static var LocationSpooferSimulatedLongitudeDefaultsKey: String = "Scyther_Location_Spoofer_Simulated_Longitude"

    // MARK: - Singleton
    private override init() { }
    static let instance: LocationSpoofer = LocationSpoofer()

    // MARK: - Data
    internal var simulatedLocation: CLLocation? {
        get {
            guard let latitude: Double = UserDefaults.standard.object(forKey: LocationSpoofer.LocationSpooferSimulatedLatitudeDefaultsKey) as? Double else {
                return nil
            }
            guard let longitude: Double = UserDefaults.standard.object(forKey: LocationSpoofer.LocationSpooferSimulatedLongitudeDefaultsKey) as? Double else {
                return nil
            }
            return CLLocation(latitude: latitude, longitude: longitude)
        }
        set {
            guard let location: CLLocation = newValue else {
                UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpooferSimulatedLatitudeDefaultsKey)
                UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpooferSimulatedLongitudeDefaultsKey)
                return
            }
            UserDefaults.standard.set(location.coordinate.latitude, forKey: LocationSpoofer.LocationSpooferSimulatedLatitudeDefaultsKey)
            UserDefaults.standard.set(location.coordinate.longitude, forKey: LocationSpoofer.LocationSpooferSimulatedLongitudeDefaultsKey)
        }
    }
    
    // MARK: - Lifecycle
    internal func start() {
        CLLocationManager.swizzle
        simulatedLocation = CLLocation(latitude: presetLocations.first?.latitude ?? 0, longitude: presetLocations.first?.longitude ?? 0)
    }
}

extension LocationSpoofer {
    internal var presetLocations: [Location]  {
        var locations: [Location] = []
        locations.append(Location(name: "Sydney, Australia",
                                  latitude: -33.868800,
                                  longitude: 151.209300))
        locations.append(Location(name: "Hong Kong, China",
                                  latitude: 22.284681,
                                  longitude: 114.158177))
        locations.append(Location(name: "London, England",
                                  latitude: 51.509980,
                                  longitude: -0.133700))
        locations.append(Location(name: "Johannesburg, South Africa",
                                  latitude: -26.204103,
                                  longitude: 28.047305))
        locations.append(Location(name: "Moscow, Russia",
                                  latitude: 55.755786,
                                  longitude: 37.617633))
        locations.append(Location(name: "Mumbai, India",
                                  latitude: 19.017615,
                                  longitude: 72.856164))
        locations.append(Location(name: "Tokyo, Japan",
                                  latitude: 35.702069,
                                  longitude: 139.775327))
        locations.append(Location(name: "Honolulu, HI, USA",
                                  latitude: 21.282778,
                                  longitude: -157.829444))
        locations.append(Location(name: "San Francisco, CA, USA",
                                  latitude: 37.787359,
                                  longitude: -122.408227))
        locations.append(Location(name: "Mexico City, Mexico",
                                  latitude: 19.435478,
                                  longitude: -99.136479))
        locations.append(Location(name: "New York, NY, USA",
                                  latitude: 40.759211,
                                  longitude: -73.984638))
        locations.append(Location(name: "Rio de Janeiro, Brazil",
                                  latitude: -22.903539,
                                  longitude: -43.209587))
        return locations
    }
}
