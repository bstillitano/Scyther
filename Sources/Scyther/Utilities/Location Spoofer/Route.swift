//
//  File.swift
//
//
//  Created by Brandon Stillitano on 29/9/21.
//

import Foundation

/// Data struct used for conveniently forming dynamic routes
struct Route {
    var id: String!
    var name: String = ""
    var fileName: String = ""
    var updateInterval: TimeInterval = 0.5
}

// MARK: - Presets
extension Route {
    static var driveCityToSuburb: Route = Route(id: "cityToSuburb",
                                                name: "Drive from city to suburb",
                                                fileName: "DriveCityToSuburb",
                                                updateInterval: 0.5)
}

extension Route: Equatable {
    public static func == (lhs: Route, rhs: Route) -> Bool {
        return lhs.id == rhs.id
    }
}
