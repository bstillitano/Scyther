//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import UIKit

/// Data struct used for conveniently forming geolocations
struct Location {
    var name: String = ""
    var latitude: CGFloat = 0.00
    var longitude: CGFloat = 0.00
}

// MARK: - Helper Functions
extension Location {
    /// Forms a valid GPX XML string using the given `Location` objects internal objects.
    var gpxString: String? {
        guard var xmlContentString = try? String(contentsOfFile: Bundle.module.path(forResource: "GenericPlace", ofType: "gpx") ?? "") else {
            return nil
        }
        xmlContentString = xmlContentString.replacingOccurrences(of: "CITY_NAME_GOES_HERE", with: "\(name)")
        xmlContentString = xmlContentString.replacingOccurrences(of: "LATITUDE_GOES_HERE", with: "\(latitude)")
        xmlContentString = xmlContentString.replacingOccurrences(of: "LONGITUDE_GOES_HERE", with: "\(longitude)")
        return xmlContentString
    }
}

// MARK: - Presets
extension Location {
    static var sydneyAustralia: Location = Location(name: "Sydney, Australia",
                                                    latitude: -33.868800,
                                                    longitude: 151.209300)
    static var hongKongChina: Location = Location(name: "Hong Kong, China",
                                                  latitude: 22.284681,
                                                  longitude: 114.158177)
    static var londonEngland: Location = Location(name: "London, England",
                                                  latitude: 51.509980,
                                                  longitude: -0.133700)
    static var johannesburgSouthAfica: Location = Location(name: "Johannesburg, South Africa",
                                                           latitude: -26.204103,
                                                           longitude: 28.047305)
    static var moscowRussia: Location = Location(name: "Moscow, Russia",
                                                 latitude: 55.755786,
                                                 longitude: 37.617633)
    static var mumbaiIndia: Location = Location(name: "Mumbai, India",
                                                latitude: 19.017615,
                                                longitude: 72.856164)
    static var tokyoJapan: Location = Location(name: "Tokyo, Japan",
                                               latitude: 35.702069,
                                               longitude: 139.775327)
    static var honoluluUSA: Location = Location(name: "Honolulu, HI, USA",
                                                latitude: 21.282778,
                                                longitude: -157.829444)
    static var sanFranciscoUSA: Location = Location(name: "San Francisco, CA, USA",
                                                    latitude: 37.787359,
                                                    longitude: -122.408227)
    static var mexicoCityMexico: Location = Location(name: "Mexico City, Mexico",
                                                     latitude: 19.435478,
                                                     longitude: -99.136479)
    static var newYorkUSA: Location = Location(name: "New York, NY, USA",
                                               latitude: 40.759211,
                                               longitude: -73.984638)
    static var rioDeJaneiroBrazil: Location = Location(name: "Rio de Janeiro, Brazil",
                                                       latitude: -22.903539,
                                                       longitude: -43.209587)
}
