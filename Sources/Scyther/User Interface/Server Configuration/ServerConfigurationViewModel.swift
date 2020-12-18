//
//  ServerConfigurationViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

#if !os(macOS)
import UIKit

internal protocol ServerConfigurationViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class ServerConfigurationViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: ServerConfigurationViewModelProtocol?

    /// Single checkable row value representing a single environment
    func checkmarkRow(identifier: String) -> CheckmarkRow {
        var row: CheckmarkRow = CheckmarkRow()
        row.text = identifier
        row.checked = ConfigurationSwitcher.instance.configuration == identifier
        row.actionBlock = { [weak self] in
            ConfigurationSwitcher.instance.configuration = identifier
            self?.prepareObjects()
        }
        return row
    }

    /// Single row representing a single environment variable
    func environmentVariable(name: String, value: String) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value

        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Environments Section
        var environmentSection: Section = Section()
        environmentSection.title = "Environment"
        environmentSection.rows = ConfigurationSwitcher.instance.configurations.sorted(by: { $0.identifier < $1.identifier }).map({ checkmarkRow(identifier: $0.identifier) })

        //Setup Variables Section
        var variablesSection: Section = Section()
        variablesSection.title = "Variables"
        variablesSection.rows = ConfigurationSwitcher.instance.environmentVariables.map({ environmentVariable(name: $0.key, value: $0.value) })

        //Setup Data
        sections.append(environmentSection)
        sections.append(variablesSection)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension ServerConfigurationViewModel {
    var title: String {
        return "Server Configuration"
    }

    var numberOfSections: Int {
        return sections.count
    }

    func title(forSection index: Int) -> String? {
        return sections[index].title
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
}

// MARK: - Private data accessors
extension ServerConfigurationViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
