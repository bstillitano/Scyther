//
//  LocationSpooferPresets.swift
//  Scyther
//
//  Created by Brandon Stillitano on 17/4/2025.
//

import Foundation

/// Enumeration of all available location spoofing presets.
///
/// This enum provides a comprehensive list of preset locations and routes that can be
/// used for location spoofing. Each preset maps to either a static `Location` or a
/// dynamic `Route`.
///
/// ## Usage
/// ```swift
/// let preset = LocationSpooferPresets.tokyo
/// if let location = preset.location {
///     LocationSpoofer.instance.spoofedLocation = location
/// }
/// ```
enum LocationSpooferPresets: String, CaseIterable {
    case driveCityToSuburb
    case berlin
    case bogota
    case cincinnati
    case denver
    case helsinki
    case lisbon
    case manila
    case marseille
    case mexicoCity
    case moscow
    case mumbai
    case nairobi
    case newYork
    case oslo
    case palermo
    case rioDeJaneiro
    case sanFrancisco
    case santiago
    case stJulian
    case stockholm
    case sydney
    case tokyo
    case valletta

    /// Returns the type category for this preset.
    ///
    /// Determines whether this preset is a static city location or a dynamic route.
    var type: LocationSpooferPresetType {
        switch self {
        case .driveCityToSuburb:
            return .route
        default:
            return .city
        }
    }

    /// Returns the static `Location` for city presets.
    ///
    /// - Returns: A `Location` object if this is a city preset, otherwise `nil`.
    var location: Location? {
        switch self {
        case .driveCityToSuburb:
            return nil
        case .berlin:
            return .berlin
        case .bogota:
            return .bogota
        case .cincinnati:
            return .cincinatti
        case .denver:
            return .denver
        case .helsinki:
            return .helsinki
        case .lisbon:
            return .lisbon
        case .manila:
            return .manila
        case .marseille:
            return .marseille
        case .mexicoCity:
            return .mexico
        case .moscow:
            return .moscow
        case .mumbai:
            return .mumbai
        case .nairobi:
            return .nairobi
        case .newYork:
            return .newYork
        case .oslo:
            return .oslo
        case .palermo:
            return .palermo
        case .rioDeJaneiro:
            return .rio
        case .sanFrancisco:
            return .sanFrancisco
        case .santiago:
            return .santiago
        case .stJulian:
            return .stJulians
        case .stockholm:
            return .stockholm
        case .sydney:
            return .sydney
        case .tokyo:
            return .tokyo
        case .valletta:
            return .valletta
        }
    }
    
    /// Returns the `Route` for route presets.
    ///
    /// - Returns: A `Route` object if this is a route preset, otherwise `nil`.
    var route: Route? {
        switch self {
        case .driveCityToSuburb:
            return .driveCityToSuburb
        default:
            return nil
        }
    }
}
