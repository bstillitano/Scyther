//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 28/6/2025.
//

import Foundation

struct ServerConfigurationListItem: Sendable, Identifiable {
    var id: String
    var name: String
    var isChecked: Bool
    var variables: [String: String]
}
