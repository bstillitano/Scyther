//
//  File.swift
//
//
//  Created by Brandon Stillitano on 29/9/21.
//

import Foundation

/// Data struct used for conveniently forming dynamic routes
public struct Route {
    public var id: String!
    public var name: String = ""
    public var fileName: String = ""
    public var updateInterval: TimeInterval = 5.0

    public init(id: String, name: String, fileName: String, updateInterval: TimeInterval) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.updateInterval = updateInterval
    }
}

// MARK: - Presets
extension Route {
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
