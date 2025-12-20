//
//  ServerConfigurationViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import Foundation

/// View model for the server configuration view.
///
/// Manages loading, filtering, and selecting server configurations. Supports searching
/// across configuration names and variable keys/values.
class ServerConfigurationViewModel: ViewModel {
    /// The list of configurations currently displayed (may be filtered by search).
    @Published var configurations: [ServerConfigurationListItem] = []

    /// Variables for the currently selected configuration.
    @Published var variables: [String: String] = [:]

    /// The current search term used to filter configurations.
    private var searchTerm: String = "" {
        didSet {
            Task { await updateData() }
        }
    }

    /// All available server configurations loaded from Scyther.
    private var items: [ServerConfiguration] = [] {
        didSet {
            Task { await updateData() }
        }
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()

        items = await Scyther.servers.all.sorted(by: { $0.id < $1.id })
    }

    /// Updates the search term and triggers a data refresh.
    ///
    /// - Parameter searchTerm: The new search term to filter by.
    func setSearchTerm(to searchTerm: String) {
        self.searchTerm = searchTerm
    }

    /// Updates the displayed configurations and variables based on the current search term.
    ///
    /// Filters configurations by searching across their IDs and variable keys/values.
    /// Always displays variables for the currently selected configuration, even if filtered out.
    private func updateData() async {
        let currentConfigurationId = await Scyther.servers.currentId

        if searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let listItems = await listItems(from: items)
            // Get variables from the source items, not from the not-yet-populated configurations
            let currentVariables = items.first { $0.id == currentConfigurationId }?.variables ?? [:]
            await MainActor.run {
                configurations = listItems
                variables = currentVariables
            }
        } else {
            let predicate = searchTerm.lowercased()
            let filteredItems = items.filter { item in
                item.id.description.lowercased().contains(predicate) ||
                    item.variables.keys.contains { $0.lowercased().contains(predicate) } ||
                    item.variables.values.contains { $0.lowercased().contains(predicate) }
            }
            let listItems = await listItems(from: filteredItems)
            let currentVariables = items.first { $0.id == currentConfigurationId }?.variables ?? [:]
            await MainActor.run {
                configurations = listItems
                variables = currentVariables
            }
        }
    }

    /// Converts server configurations to list items with selection state.
    ///
    /// - Parameter items: The configurations to convert.
    /// - Returns: List items with the currently selected configuration marked.
    private func listItems(from items: [ServerConfiguration]) async -> [ServerConfigurationListItem] {
        let currentConfiguration = await Scyther.servers.currentId
        return items.map { configuration in
            ServerConfigurationListItem(
                id: configuration.id,
                name: configuration.id,
                isChecked: configuration.id == currentConfiguration,
                variables: configuration.variables
            )
        }
    }

    /// Selects a new server configuration and refreshes the view.
    ///
    /// - Parameter configuration: The configuration to select.
    func didSelectConfiguration(_ configuration: ServerConfigurationListItem) async {
        await Scyther.servers.select(configuration.id)
        await updateData()
    }
}
