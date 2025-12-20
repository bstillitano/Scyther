//
//  LocationSpooferPresetType.swift
//  Scyther
//
//  Created by Brandon Stillitano on 17/4/2025.
//

import Foundation

/// Categories of location spoofing presets available in the UI.
///
/// This enum categorizes the different types of location spoofing options
/// that users can select from the Location Spoofer interface.
enum LocationSpooferPresetType: String, CaseIterable {
    /// Static city locations (e.g., Tokyo, Sydney, New York).
    case city

    /// Dynamic routes that simulate movement (e.g., driving routes).
    case route

    /// Custom user-defined coordinates.
    case custom

    /// Returns a human-readable label for display in the UI.
    ///
    /// - Returns: A localized string describing the preset type.
    var label: String {
        switch self {
        case .city:
            "Cities"
        case .route:
            "Routes"
        case .custom:
            "Custom"
        }
    }
}
