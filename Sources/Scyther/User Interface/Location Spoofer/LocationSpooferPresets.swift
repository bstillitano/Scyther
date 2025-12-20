//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 17/4/2025.
//

import Foundation

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

    var type: LocationSpooferPresetType {
        switch self {
        case .driveCityToSuburb:
            return .route
        default:
            return .city
        }
    }
    
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
    
    var route: Route? {
        switch self {
        case .driveCityToSuburb:
            return .driveCityToSuburb
        default:
            return nil
        }
    }
}
