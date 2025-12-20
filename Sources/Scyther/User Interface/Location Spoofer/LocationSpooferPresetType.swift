//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 17/4/2025.
//

import Foundation

enum LocationSpooferPresetType: String, CaseIterable {
    case city
    case route
    case custom
    
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
