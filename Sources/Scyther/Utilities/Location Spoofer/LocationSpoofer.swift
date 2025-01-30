//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import CoreLocation

struct LocationSpooferConfiguration {
    static var updateInterval = 0.5
    static var GpxFileName: String?
}

internal class LocationSpoofer: CLLocationManager {
    // MARK: - Static Data
    internal static var LocationSpoofingEnabledChangeNotification: NSNotification.Name = NSNotification.Name("LocationSpoofingEnabledChangeNotification")
    internal static var LocationSpoofingLocationChangeNotification: NSNotification.Name = NSNotification.Name("LocationSpoofingLocationChangeNotification")
    internal static var LocationSpoofingEnabledDefaultsKey: String = "Scyther_Location_Spoofing_Enabled"
    internal static var LocationSpoofingCustomLocationEnabledDefaultsKey: String = "Scyther_Location_Spoofing_Custom_Location_Enabled"
    internal static var LocationSpoofingLongitudeKey: String = "Scyther_Location_Spoofing_Longitude"
    internal static var LocationSpoofingLatitudeKey: String = "Scyther_Location_Spoofing_Latitude"
    internal static var LocationSpoofingCustomLongitudeKey: String = "Scyther_Location_Spoofing_Custom_Longitude"
    internal static var LocationSpoofingCustomLatitudeKey: String = "Scyther_Location_Spoofing_Custom_Latitude"
    internal static var LocationSpoofingRouteIdKey: String = "Scyther_Location_Spoofing_Route_Id"

    // MARK: - Singleton
    private override init() {
        locations = Queue<CLLocation>()
    }
    static let instance = LocationSpoofer()

    // MARK: - Data
    private var parser: GPXParser?
    private var timer: Timer?
    private var locations: Queue<CLLocation>?
    internal var developerLocations: [Location] = []
    var updateInterval: TimeInterval = 0.5
    internal var spoofingEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: LocationSpoofer.LocationSpoofingEnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: LocationSpoofer.LocationSpoofingEnabledDefaultsKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingEnabledChangeNotification, object: newValue)
        }
    }
    internal var useCustomLocation: Bool {
        get {
            UserDefaults.standard.bool(forKey: LocationSpoofer.LocationSpoofingCustomLocationEnabledDefaultsKey)
        } set {
            UserDefaults.standard.setValue(newValue, forKey: LocationSpoofer.LocationSpoofingCustomLocationEnabledDefaultsKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification, object: newValue)
        }
    }
    internal var customLocation: Location {
        get {
            let latitude = UserDefaults.standard.value(forKey: LocationSpoofer.LocationSpoofingCustomLatitudeKey) as? Double
            let longitude = UserDefaults.standard.value(forKey: LocationSpoofer.LocationSpoofingCustomLongitudeKey) as? Double
            return Location(id: "custom",
                            name: "Custom Location",
                            latitude: latitude ?? .zero,
                            longitude: longitude ?? .zero)
        }
        set {
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingCustomLatitudeKey)
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingCustomLongitudeKey)
            UserDefaults.standard.setValue(newValue.latitude, forKey: LocationSpoofer.LocationSpoofingCustomLatitudeKey)
            UserDefaults.standard.setValue(newValue.longitude, forKey: LocationSpoofer.LocationSpoofingCustomLongitudeKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification, object: newValue)
        }
    }
    internal var spoofedLocation: Location {
        get {
            if useCustomLocation {
                return customLocation
            } else {
                let latitude = UserDefaults.standard.value(forKey: LocationSpoofer.LocationSpoofingLatitudeKey) as? Double
                let longitude = UserDefaults.standard.value(forKey: LocationSpoofer.LocationSpoofingLongitudeKey) as? Double
                return presetLocations.first(where: { $0.latitude == latitude && $0.longitude == longitude }) ?? .sydney
            }
        }
        set {
            UserDefaults.standard.setValue(false, forKey: LocationSpoofer.LocationSpoofingCustomLocationEnabledDefaultsKey)
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingLatitudeKey)
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingLongitudeKey)
            UserDefaults.standard.setValue(newValue.latitude, forKey: LocationSpoofer.LocationSpoofingLatitudeKey)
            UserDefaults.standard.setValue(newValue.longitude, forKey: LocationSpoofer.LocationSpoofingLongitudeKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification, object: newValue)
        }
    }
    internal var spoofedRoute: Route? {
        get {
            return presetRoutes.first(where: { $0.id == UserDefaults.standard.string(forKey: LocationSpoofer.LocationSpoofingRouteIdKey) })
        }
        set {
            guard newValue != nil else {
                UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingRouteIdKey)
                return
            }
            UserDefaults.standard.setValue(newValue?.id, forKey: LocationSpoofer.LocationSpoofingRouteIdKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification,
                                            object: newValue)
        }
    }

    // MARK: - Lifecycle
    override func startUpdatingLocation() {
        guard delegate != nil else {
            return
        }
        guard spoofingEnabled else {
            super.startUpdatingLocation()
            return
        }
        timer = Timer(timeInterval: updateInterval, repeats: true, block: { [weak self] _ in
            self?.updateLocation()
        })
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .default)
        }
    }

    override func stopUpdatingLocation() {
        guard spoofingEnabled else {
            super.stopUpdatingLocation()
            return
        }
        timer?.invalidate()
    }

    override func requestLocation() {
        guard spoofingEnabled else {
            super.requestLocation()
            return
        }
        if let location = locations?.peek() {
            delegate?.locationManager?(self, didUpdateLocations: [location])
        }
    }

    internal func setCustomLocation(_ location: CLLocationCoordinate2D) {
        customLocation = Location(id: "custom",
                                  name: "Custom Location",
                                  latitude: location.latitude,
                                  longitude: location.longitude)
    }
}

// MARK: - Spoofing
extension LocationSpoofer {
    internal func start() {
        registerForSpoofingEnabledNotifications()
        registerForLocationChangeNotifications()
        swizzle()
    }

    private func swizzle() {
        if spoofingEnabled {
            CLLocationManager.swizzleLocationUpdates
        } else {
            CLLocationManager.unswizzleLocationUpdates
        }
    }

    func startMocks(usingGPX fileName: String) {
        parser = GPXParser(forResource: fileName, ofType: "gpx")
        parser?.delegate = self
        parser?.parse()
    }

    func startMocks(usingLocation location: Location) {
        parser = GPXParser(forLocation: location)
        parser?.delegate = self
        parser?.parse()
    }

    func startMocks() {
        guard let route: Route = spoofedRoute else {
            updateInterval = 0.5
            startMocks(usingLocation: spoofedLocation)
            return
        }
        updateInterval = route.updateInterval
        startMocks(usingGPX: route.fileName)
    }

    private func updateLocation() {
        if let location = locations?.dequeue() {
            delegate?.locationManager?(self, didUpdateLocations: [location])
            if let isEmpty = locations?.isEmpty(), isEmpty {
                logMessage("stopping at: \(location.coordinate)")
                stopUpdatingLocation()
            }
        }
    }
}

// MARK: - Spoofing Enabled Notifications
internal extension LocationSpoofer {
    func registerForSpoofingEnabledNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(spoofingEnabledChanged),
                                               name: LocationSpoofer.LocationSpoofingEnabledChangeNotification,
                                               object: nil)
    }

    @objc
    func spoofingEnabledChanged() {
        swizzle()
        guard spoofingEnabled else {
            guard delegate != nil else {
                return
            }
            requestLocation()
            return
        }
        spoofedLocationChanged()
    }
}

// MARK: - Location Change Notifications
internal extension LocationSpoofer {
    func registerForLocationChangeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(spoofedLocationChanged),
                                               name: LocationSpoofer.LocationSpoofingLocationChangeNotification,
                                               object: nil)
    }

    @objc
    func spoofedLocationChanged() {
        startMocks()
    }
}

extension LocationSpoofer: GPXParsingProtocol {
    func parser(_ parser: GPXParser, didCompleteParsing locations: Queue<CLLocation>) {
        self.locations = locations
        self.startUpdatingLocation()
    }
}

extension LocationSpoofer {
    internal var presetLocations: [Location] {
        return [.sydney,
                    .helsinki,
                    .santiago,
                    .rio,
                    .denver,
                    .cincinatti,
                    .moscow,
                    .tokyo,
                    .palermo,
                    .bogota,
                    .berlin,
                    .oslo,
                    .nairobi,
                    .marseille,
                    .manila,
                    .newYork,
                    .mumbai,
                    .sanFrancisco,
                    .mexico,
                    .stJulians,
                    .valletta,
                    .stockholm,
                    .lisbon]
    }

    internal var presetRoutes: [Route] {
        return [.driveCityToSuburb]
    }
    
    public func addLocation(_ location: Location) {
        developerLocations.append(location)
    }
}
