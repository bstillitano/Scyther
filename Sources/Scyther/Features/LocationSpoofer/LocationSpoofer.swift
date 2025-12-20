//
//  LocationSpoofer.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import CoreLocation

/// Configuration settings for the location spoofer.
///
/// - Note: This is an internal configuration struct used by `LocationSpoofer`.
struct LocationSpooferConfiguration {
    /// Default time interval between location updates (in seconds).
    static var updateInterval = 0.5

    /// Optional GPX file name to load for location simulation.
    static var GpxFileName: String?
}

/// A location manager that provides spoofed GPS coordinates for testing.
///
/// `LocationSpoofer` extends `CLLocationManager` to intercept location requests and provide
/// fake coordinates instead of real device location. It supports both static locations and
/// dynamic routes, making it useful for testing location-based features without physical movement.
///
/// ## Features
/// - Spoof static locations or animated routes
/// - Support for preset cities and custom coordinates
/// - Method swizzling to intercept Core Location calls
/// - Persistent location settings via UserDefaults
/// - GPX file parsing for complex routes
/// - Developer-configurable custom locations
///
/// ## Usage
/// ```swift
/// // Enable location spoofing
/// LocationSpoofer.instance.spoofingEnabled = true
///
/// // Set a static location
/// LocationSpoofer.instance.spoofedLocation = .tokyo
///
/// // Set a custom location
/// LocationSpoofer.instance.setCustomLocation(
///     CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
/// )
///
/// // Set a route for simulated movement
/// LocationSpoofer.instance.spoofedRoute = .driveCityToSuburb
///
/// // Now all CLLocationManager calls will use spoofed coordinates
/// ```
///
/// - Important: Location spoofing only affects the current app. System location services
///   and other apps will continue to use real GPS coordinates.
///
/// - Note: Call `LocationSpoofer.instance.start()` during app initialization to enable swizzling.
public final class LocationSpoofer: CLLocationManager {
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
    public var spoofingEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: LocationSpoofer.LocationSpoofingEnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: LocationSpoofer.LocationSpoofingEnabledDefaultsKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingEnabledChangeNotification, object: newValue)
        }
    }
    public var useCustomLocation: Bool {
        get {
            UserDefaults.standard.bool(forKey: LocationSpoofer.LocationSpoofingCustomLocationEnabledDefaultsKey)
        } set {
            UserDefaults.standard.setValue(newValue, forKey: LocationSpoofer.LocationSpoofingCustomLocationEnabledDefaultsKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification, object: newValue)
        }
    }
    public var customLocation: Location {
        get {
            let latitude = UserDefaults.standard.value(forKey: LocationSpoofer.LocationSpoofingCustomLatitudeKey) as? Double
            let longitude = UserDefaults.standard.value(forKey: LocationSpoofer.LocationSpoofingCustomLongitudeKey) as? Double
            return Location(id: "custom",
                            name: "Custom Location",
                            latitude: latitude ?? .zero,
                            longitude: longitude ?? .zero)
        }
        set {
            // Clear route when setting custom location
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingRouteIdKey)
            // Set custom location
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingCustomLatitudeKey)
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingCustomLongitudeKey)
            UserDefaults.standard.setValue(newValue.latitude, forKey: LocationSpoofer.LocationSpoofingCustomLatitudeKey)
            UserDefaults.standard.setValue(newValue.longitude, forKey: LocationSpoofer.LocationSpoofingCustomLongitudeKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification, object: newValue)
        }
    }
    public var spoofedLocation: Location {
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
            // Clear other modes
            UserDefaults.standard.setValue(false, forKey: LocationSpoofer.LocationSpoofingCustomLocationEnabledDefaultsKey)
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingRouteIdKey)
            // Set location
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingLatitudeKey)
            UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingLongitudeKey)
            UserDefaults.standard.setValue(newValue.latitude, forKey: LocationSpoofer.LocationSpoofingLatitudeKey)
            UserDefaults.standard.setValue(newValue.longitude, forKey: LocationSpoofer.LocationSpoofingLongitudeKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification, object: newValue)
        }
    }
    public var spoofedRoute: Route? {
        get {
            return presetRoutes.first(where: { $0.id == UserDefaults.standard.string(forKey: LocationSpoofer.LocationSpoofingRouteIdKey) })
        }
        set {
            // Clear other modes
            UserDefaults.standard.setValue(false, forKey: LocationSpoofer.LocationSpoofingCustomLocationEnabledDefaultsKey)

            guard let newValue = newValue else {
                UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingRouteIdKey)
                return
            }
            UserDefaults.standard.setValue(newValue.id, forKey: LocationSpoofer.LocationSpoofingRouteIdKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification,
                                            object: newValue)
        }
    }

    // MARK: - Lifecycle
    public override func startUpdatingLocation() {
        guard delegate != nil else {
            return
        }
        timer = Timer(timeInterval: updateInterval, repeats: true, block: { [weak self] _ in
            self?.updateLocation()
        })
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .default)
        }
    }

    public override func stopUpdatingLocation() {
        timer?.invalidate()
    }

    public override func requestLocation() {
        if let location = locations?.peek() {
            delegate?.locationManager?(self, didUpdateLocations: [location])
        }
    }

    public func setCustomLocation(_ location: CLLocationCoordinate2D) {
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
            CLLocationManager.swizzleLocationUpdates()
        } else {
            CLLocationManager.unswizzleLocationUpdates()
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
        // If queue is empty and no route (single location), re-populate
        if locations?.isEmpty() == true && spoofedRoute == nil {
            startMocks(usingLocation: spoofedLocation)
        }

        if let location = locations?.dequeue() {
            delegate?.locationManager?(self, didUpdateLocations: [location])
            // Only stop for routes when complete, not for single locations
            if let isEmpty = locations?.isEmpty(), isEmpty, spoofedRoute != nil {
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
