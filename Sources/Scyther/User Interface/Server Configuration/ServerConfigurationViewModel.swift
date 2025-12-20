//
//  ServerConfigurationViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import Foundation
import ScytherExtensions

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
        if searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let items = await listItems(from: items)
            let currentConfiguration = await ConfigurationSwitcher.instance.configuration
            let currentVariables = configurations.first { $0.id == currentConfiguration }?.variables ?? [:]
            await MainActor.run {
                configurations = items
                variables = currentVariables
            }
        } else {
            let predicate = searchTerm.lowercased()
            let filteredItems = items.filter { item in
                item.id.description.lowercased().contains(predicate) ||
                    item.variables.keys.filter { $0.lowercased().contains(predicate) }.isEmpty == false ||
                    item.variables.values.filter { $0.lowercased().contains(predicate) }.isEmpty == false
            }
            let items = await listItems(from: filteredItems)
            await MainActor.run {
                configurations = items
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
