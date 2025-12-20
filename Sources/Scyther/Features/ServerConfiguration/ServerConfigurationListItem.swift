//
//  ServerConfigurationListItem.swift
//  Scyther
//
//  Created by Brandon Stillitano on 28/6/2025.
//

import Foundation

/// A view model item representing a server configuration in a list.
///
/// This structure extends `ServerConfiguration` with UI-specific properties like
/// selection state, making it suitable for display in a list view.
struct ServerConfigurationListItem: Sendable, Identifiable {
    /// The unique identifier for this configuration (matches the configuration name).
    var id: String

    /// The display name of the configuration.
    var name: String

    /// Whether this configuration is currently selected.
    var isChecked: Bool

    /// The configuration variables associated with this server configuration.
    var variables: [String: String]
}
