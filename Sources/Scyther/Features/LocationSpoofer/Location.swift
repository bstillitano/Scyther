//
//  Location.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import UIKit

/// A structure representing a geographic location with coordinates and metadata.
///
/// `Location` provides a convenient way to define and work with geographic coordinates
/// for location spoofing. It includes preset locations for major cities worldwide and
/// can generate GPX strings for location simulation.
///
/// ## Features
/// - Stores latitude/longitude coordinates
/// - Human-readable location names
/// - Unique identifiers for each location
/// - GPX file generation for location simulation
/// - Equatable conformance for comparison
///
/// ## Usage
/// ```swift
/// // Use a preset location
/// let sydney = Location.sydney
///
/// // Create a custom location
/// let custom = Location(
///     id: "office",
///     name: "Office",
///     latitude: 37.7749,
///     longitude: -122.4194
/// )
///
/// // Generate GPX data
/// let gpx = sydney.gpxString
/// ```
public struct Location {
    /// Unique identifier for the location.
    public var id: String

    /// Human-readable name of the location (e.g., "Sydney, Australia").
    public var name: String = ""

    /// Latitude coordinate in decimal degrees.
    public var latitude: Double = 0.00

    /// Longitude coordinate in decimal degrees.
    public var longitude: Double = 0.00

    /// Creates a new location with the specified parameters.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the location.
    ///   - name: Human-readable name of the location.
    ///   - latitude: Latitude coordinate in decimal degrees.
    ///   - longitude: Longitude coordinate in decimal degrees.
    public init(id: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Helper Functions
extension Location {
    /// Generates a GPX (GPS Exchange Format) XML string for this location.
    ///
    /// This property creates a GPX file representation of the location by loading a
    /// template file and replacing placeholders with the location's actual data.
    /// The GPX format is used by the location spoofer to simulate GPS coordinates.
    ///
    /// ## Example
    /// ```swift
    /// let sydney = Location.sydney
    /// if let gpx = sydney.gpxString {
    ///     // Use GPX string for location simulation
    ///     print(gpx)
    /// }
    /// ```
    ///
    /// - Returns: A GPX XML string, or `nil` if the template file cannot be loaded.
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
/// Extension providing preset locations for major cities worldwide.
///
/// These preset locations can be used directly for location spoofing without
/// needing to manually specify coordinates.
extension Location {
    /// Sydney, Australia (-33.8688, 151.2093)
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
                                              name: "St. Julian, Malta",
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
