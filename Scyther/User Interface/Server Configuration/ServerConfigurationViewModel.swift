//
//  ServerConfigurationViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import UIKit

internal class ServerConfigurationViewModel {
    /// Single checkable row value representing a single environment
    static func checkmarkRow(identifier: String) -> CheckmarkRow {
        //Setup Row
        var row: CheckmarkRow = CheckmarkRow()
        row.text = identifier
        row.checked = ConfigurationSwitcher.instance.configuration == identifier
        row.actionBlock = {
            ConfigurationSwitcher.instance.configuration = identifier
        }
        return row
    }
    
    /// Single row representing a single environment variable
    static func environmentVariable(name: String, value: String) -> DefaultRow {
        //Setup Row
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value
        
        return row
    }
    
    /// Enum which defines each section of the ViewModel. Contains title and row data.
    enum Section: Int, CaseIterable {
        case environment
        case variables

        /// String representation of the section that acts as a very short descriptor.
        var title: String? {
            switch self {
            case .environment: return "Environment"
            case .variables: return "Variables"
            }
        }

        /// Row definitions for each section of the ViewModel.
        var rows: [Row] {
            switch self {
            case .environment:
                return ConfigurationSwitcher.instance.configurations.sorted(by: { $0.identifier < $1.identifier }).map( { checkmarkRow(identifier: $0.identifier) })
            case .variables:
                return ConfigurationSwitcher.instance.environmentVariables.map( { environmentVariable(name: $0.key, value: $0.value) })
            }
        }
    }
}

// MARK: - Public data accessors
extension ServerConfigurationViewModel {
    var title: String {
        return "Server Configuration"
    }

    var numberOfSections: Int {
        return Section.allCases.count
    }

    func title(forSection index: Int) -> String? {
        return Section(rawValue: index)?.title
    }

    func numbeOfRows(inSection index: Int) -> Int {
        return rows(inSection: index)?.count ?? 0
    }

    internal func row(at indexPath: IndexPath) -> Row? {
        guard let rows = rows(inSection: indexPath.section) else { return nil }
        guard rows.indices.contains(indexPath.row) else { return nil }
        return rows[indexPath.row]
    }

    func title(for row: Row, indexPath: IndexPath) -> String? {
        return row.text
    }

    func performAction(for row: Row, indexPath: IndexPath) {
        row.actionBlock?()
    }

    // MARK: - Private data accessors
    private func section(for index: Int) -> Section? {
        return Section(rawValue: index)
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
