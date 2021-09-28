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
    internal static var LocationSpoofingIdKey: String = "Scyther_Location_Spoofing_Id"

    // MARK: - Singleton
    private override init() {
        locations = Queue<CLLocation>()
    }
    static let instance = LocationSpoofer()

    // MARK: - Data
    private var parser: GPXParser?
    private var timer: Timer?
    private var locations: Queue<CLLocation>?
    var updateInterval: TimeInterval = 0.5
    var isRunning: Bool = false
    internal var spoofingEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: LocationSpoofer.LocationSpoofingEnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: LocationSpoofer.LocationSpoofingEnabledDefaultsKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingEnabledChangeNotification,
                                            object: newValue)
        }
    }
    internal var spoofedLocation: Location? {
        get {
            return presetLocations.first(where: { $0.id == UserDefaults.standard.string(forKey: LocationSpoofer.LocationSpoofingIdKey) })
        }
        set {
            guard newValue != nil else {
                UserDefaults.standard.removeObject(forKey: LocationSpoofer.LocationSpoofingIdKey)
                NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification,
                                                object: newValue)
                return
            }
            UserDefaults.standard.setValue(newValue?.id, forKey: LocationSpoofer.LocationSpoofingIdKey)
            NotificationCenter.default.post(name: LocationSpoofer.LocationSpoofingLocationChangeNotification,
                                            object: newValue)
        }
    }

    // MARK: - Lifecycle
    override func startUpdatingLocation() {
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
        isRunning = false
        locations = nil
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
}

// MARK: - Spoofing
extension LocationSpoofer {
    internal func start() {
        registerForSpoofingEnabledNotifications()
        registerForLocationChangeNotifications()
        CLLocationManager.swizzleLocationUpdates
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

    func stopMocking() {
        self.stopUpdatingLocation()
    }

    private func updateLocation() {
        if let location = locations?.dequeue() {
            isRunning = true
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
        guard spoofingEnabled else {
            locations = nil
            requestLocation()
            return
        }
        startMocks(usingLocation: spoofedLocation ?? .sydneyAustralia)
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
        startMocks(usingLocation: spoofedLocation ?? .sydneyAustralia)
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
