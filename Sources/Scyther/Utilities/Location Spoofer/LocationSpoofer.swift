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
    internal static var LocationSpoofingEnabledDefaultsKey: String = "Scyther_Interface_Toolkit_Slow_Animations_Enabled"
    internal static var LocationSpoofingCityNameKey: String = "Scyther_Interface_Toolkit_View_Borders_Enabled"
    internal static var LocationSpoofingCityLatitudeKey: String = "Scyther_Interface_Toolkit_Visualise_Touches_Enabled"
    internal static var LocationSpoofingCityLongitudeKey: String = "Scyther_Interface_Toolkit_Visualise_Touches_Enabled"

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

    // MARK: - Lifecycle
    override func startUpdatingLocation() {
        timer = Timer(timeInterval: updateInterval, repeats: true, block: {
            [unowned self](_) in
            self.updateLocation()
        })
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .default)
        }
    }

    override func stopUpdatingLocation() {
        timer?.invalidate()
        isRunning = false
    }

    override func requestLocation() {
        if let location = locations?.peek() {
            delegate?.locationManager?(self, didUpdateLocations: [location])
        }
    }
}

// MARK: - Spoofing
extension LocationSpoofer {
    internal func start() {
        CLLocationManager.swizzleLocationUpdates
    }

    func startMocks(usingGPX fileName: String) {
        parser = GPXParser(forResource: fileName, ofType: "gpx")
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
                print("stopping at: \(location.coordinate)")
                stopUpdatingLocation()
            }
        }
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
