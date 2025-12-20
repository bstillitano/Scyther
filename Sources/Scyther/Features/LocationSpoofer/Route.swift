//
//  Route.swift
//
//
//  Created by Brandon Stillitano on 29/9/21.
//

import Foundation

/// A structure representing a simulated movement route for location spoofing.
///
/// `Route` defines a path through multiple GPS coordinates read from a GPX file.
/// Unlike static `Location` objects, routes simulate movement by updating the
/// spoofed location at regular intervals as the device "moves" along the path.
///
/// ## Features
/// - Loads coordinates from GPX files
/// - Configurable update intervals for realistic movement
/// - Preset routes for common scenarios
/// - Equatable conformance for comparison
///
/// ## Usage
/// ```swift
/// // Use a preset route
/// let drive = Route.driveCityToSuburb
///
/// // Create a custom route
/// let route = Route(
///     id: "morning-commute",
///     name: "Morning Commute",
///     fileName: "CommutRoute",
///     updateInterval: 3.0
/// )
/// ```
public struct Route {
    /// Unique identifier for the route.
    public var id: String!

    /// Human-readable name of the route (e.g., "Drive from city to suburb").
    public var name: String = ""

    /// Name of the GPX file (without extension) containing the route coordinates.
    public var fileName: String = ""

    /// Time interval in seconds between location updates along the route.
    ///
    /// Lower values create smoother, more realistic movement but update more frequently.
    public var updateInterval: TimeInterval = 5.0

    /// Creates a new route with the specified parameters.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the route.
    ///   - name: Human-readable name of the route.
    ///   - fileName: Name of the GPX file (without extension) containing coordinates.
    ///   - updateInterval: Time in seconds between location updates.
    public init(id: String, name: String, fileName: String, updateInterval: TimeInterval) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.updateInterval = updateInterval
    }
}

// MARK: - Presets
/// Extension providing preset routes for common scenarios.
extension Route {
    /// A simulated driving route from a city center to suburban area.
    ///
    /// Updates every 5 seconds to simulate realistic driving speed.
    static var driveCityToSuburb: Route = Route(id: "cityToSuburb",
                                                name: "Drive from city to suburb",
                                                fileName: "DriveCityToSuburb",
                                                updateInterval: 5.0)
}

extension Route: Equatable {
    public static func == (lhs: Route, rhs: Route) -> Bool {
        return lhs.id == rhs.id
    }
}
