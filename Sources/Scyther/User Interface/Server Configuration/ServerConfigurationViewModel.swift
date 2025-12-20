//
//  ServerConfigurationViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import Foundation

class ServerConfigurationViewModel: ViewModel {
    @Published var configurations: [ServerConfigurationListItem] = []
    @Published var variables: [String: String] = [:]

    private var searchTerm: String = "" {
        didSet {
            Task { await updateData() }
        }
    }

    private var items: [ServerConfiguration] = [] {
        didSet {
            Task { await updateData() }
        }
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()

        items = await ConfigurationSwitcher.instance.configurations.sorted(by: { $0.id < $1.id })
    }

    func setSearchTerm(to searchTerm: String) {
        self.searchTerm = searchTerm
    }

    private func updateData() async {
        let currentConfigurationId = await ConfigurationSwitcher.instance.configuration

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

    private func listItems(from items: [ServerConfiguration]) async -> [ServerConfigurationListItem] {
        let currentConfiguration = await ConfigurationSwitcher.instance.configuration
        return items.map { configuration in
            ServerConfigurationListItem(
                id: configuration.id,
                name: configuration.id,
                isChecked: configuration.id == currentConfiguration,
                variables: configuration.variables
            )
        }
    }
    
    func didSelectConfiguration(_ configuration: ServerConfigurationListItem) async {
        await ConfigurationSwitcher.instance.setConfiguration(configuration.id)
        await updateData()
    }
}
