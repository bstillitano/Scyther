//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import UIKit

/// Data struct used for conveniently forming geolocations
struct Location {
    var id: String!
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
    static var sydney: Location = Location(id: "sydney",
                                           name: "Sydney, Australia",
                                           latitude: -33.8688,
                                           longitude: 151.2093)
    static var helsinki: Location = Location(id: "helsinki",
                                             name: "Helsinki, Finland",
                                             latitude: 60.1699,
                                             longitude: 24.9384)
    static var santiago: Location = Location(id: "santiago",
                                             name: "Santiago, Chile",
                                             latitude: -33.4489,
                                             longitude: -70.669)
    static var rio: Location = Location(id: "rio",
                                        name: "Rio de Janeiro, Brazil",
                                        latitude: -22.9068,
                                        longitude: -43.1729)
    static var denver: Location = Location(id: "denver",
                                           name: "Denver, USA",
                                           latitude: 39.7392,
                                           longitude: -104.9903)
    static var cincinatti: Location = Location(id: "cincinatti",
                                               name: "Cincinnati, USA",
                                               latitude: 39.1031,
                                               longitude: -84.5120)
    static var moscow: Location = Location(id: "moscow",
                                           name: "Moscow, Russia",
                                           latitude: 55.7558,
                                           longitude: 37.6173)
    static var tokyo: Location = Location(id: "tokyo",
                                          name: "Tokyo, Japan",
                                          latitude: 35.6762,
                                          longitude: 139.6503)
    static var palermo: Location = Location(id: "palermo",
                                            name: "Palermo, Italy",
                                            latitude: 38.1157,
                                            longitude: 13.3615)
    static var bogota: Location = Location(id: "bogota",
                                           name: "Bogotá, Colombia",
                                           latitude: 4.7110,
                                           longitude: -74.0721)
    static var berlin: Location = Location(id: "berlin",
                                           name: "Berlin, Germany",
                                           latitude: 52.5200,
                                           longitude: 13.4050)
    static var oslo: Location = Location(id: "oslo",
                                         name: "Oslo, Norway",
                                         latitude: 59.9139,
                                         longitude: 10.7522)
    static var nairobi: Location = Location(id: "nairobi",
                                            name: "Nairobi, Kenya",
                                            latitude: -1.2921,
                                            longitude: 36.8219)
    static var marseille: Location = Location(id: "maresille",
                                              name: "Marseille, France",
                                              latitude: 43.2965,
                                              longitude: 5.3698)
    static var manila: Location = Location(id: "manila",
                                           name: "Manila, Phillipines",
                                           latitude: 14.5995,
                                           longitude: 120.9842)
    static var newYork: Location = Location(id: "newYork",
                                            name: "New York, USA",
                                            latitude: 40.7128,
                                            longitude: -74.0060)
    static var mumbai: Location = Location(id: "mumbai",
                                           name: "Mumbai, India",
                                           latitude: 19.0760,
                                           longitude: 72.8777)
    static var sanFrancisco: Location = Location(id: "sanFranciso",
                                                 name: "San Francisco, USA",
                                                 latitude: 37.7749,
                                                 longitude: -122.4194)
    static var mexico: Location = Location(id: "mexico",
                                           name: "Mexico City, Mexico",
                                           latitude: 19.435478,
                                           longitude: -99.136479)
    static var stJulians: Location = Location(id: "stJulians",
                                              name: "St. Julians, Malta",
                                              latitude: 35.9181,
                                              longitude: 14.4883)
    static var valletta: Location = Location(id: "valletta",
                                             name: "Valletta, Malta",
                                             latitude: 35.8989,
                                             longitude: 14.5146)
    static var stockholm: Location = Location(id: "stockholm",
                                              name: "Stockholm, Sweden",
                                              latitude: 59.3293,
                                              longitude: 18.0686)
    static var lisbon: Location = Location(id: "lisbon",
                                           name: "Lisbon, Portugal",
                                           latitude: 38.7223,
                                           longitude: -9.1393)
}

extension Location: Equatable {
    public static func == (lhs: Location, rhs: Location) -> Bool {
        return lhs.id == rhs.id
    }
}
