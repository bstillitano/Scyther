//
//  MKCoordinateRegion+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 30/1/2025.
//

import Foundation
import MapKit

/// Provides Equatable conformance for MKCoordinateRegion.
///
/// This extension adds Equatable protocol conformance to MKCoordinateRegion using Swift's
/// retroactive conformance feature, allowing coordinate regions to be compared for equality.
extension MKCoordinateRegion: @retroactive Equatable {
    /// Compares two coordinate regions for equality based on their center coordinates.
    ///
    /// Two regions are considered equal if their center coordinates (latitude and longitude)
    /// are identical. The span (zoom level) is not considered in this comparison.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side coordinate region
    ///   - rhs: The right-hand side coordinate region
    ///
    /// - Returns: `true` if both regions have the same center coordinates, `false` otherwise.
    ///
    /// ## Example
    /// ```swift
    /// let region1 = MKCoordinateRegion(
    ///     center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    ///     span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    /// )
    ///
    /// let region2 = MKCoordinateRegion(
    ///     center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    ///     span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    /// )
    ///
    /// print(region1 == region2) // Prints "true" (same center, different span)
    /// ```
    ///
    /// - Note: This implementation only compares the center coordinates and ignores the span.
    ///         Two regions with the same center but different zoom levels are considered equal.
    static public func == (lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        return lhs.center.latitude == rhs.center.latitude &&
            lhs.center.longitude == rhs.center.longitude
    }
}
