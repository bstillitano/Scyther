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
        simulatedLocation = CLLocation(latitude: Location.sydneyAustralia.latitude,
                                       longitude: Location.sydneyAustralia.longitude)
    }
}

extension LocationSpoofer {
    internal var presetLocations: [Location] {
        return [
            .sydneyAustralia,
            .hongKongChina,
            .londonEngland,
            .johannesburgSouthAfica,
            .moscowRussia,
            .mumbaiIndia,
            .tokyoJapan,
            .honoluluUSA,
            .sanFranciscoUSA,
            .mexicoCityMexico,
            .newYorkUSA,
            .rioDeJaneiroBrazil
        ]
    }
}
