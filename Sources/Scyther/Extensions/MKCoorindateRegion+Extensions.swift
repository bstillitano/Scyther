//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 30/1/2025.
//

import Foundation
import MapKit

extension MKCoordinateRegion: @retroactive Equatable {
    static public func == (lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        return lhs.center.latitude == rhs.center.latitude &&
            lhs.center.longitude == rhs.center.longitude
    }
}
