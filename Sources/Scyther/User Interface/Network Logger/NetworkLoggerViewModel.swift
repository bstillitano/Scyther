//
//  NetworkLoggerViewModel.swift
//  
//
//  Created by Brandon Stillitano on 24/12/20.
//

#if !os(macOS)
import UIKit

internal protocol NetworkLoggerViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class NetworkLoggerViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: NetworkLoggerViewModelProtocol?

    /// Single checkable row value representing a single environment
    func networkRow(identifier: String) -> CheckmarkRow {
        var row: CheckmarkRow = CheckmarkRow()
        row.text = identifier
        row.checked = ConfigurationSwitcher.instance.configuration == identifier
        row.actionBlock = { [weak self] in
            ConfigurationSwitcher.instance.configuration = identifier
            self?.prepareObjects()
        }
        return row
    }

    func prepareObjects() {
        /// Clear Data
        sections.removeAll()

        /// Setup Logs Section
        var logsSection: Section = Section()
        logsSection.title = nil
//        logsSection.rows = ConfigurationSwitcher.instance.configurations.sorted(by: { $0.identifier < $1.identifier }).map({ checkmarkRow(identifier: $0.identifier) })

        /// Setup Data
        sections.append(logsSection)

        /// Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension NetworkLoggerViewModel {
    var title: String {
        return "Network Logger"
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
extension NetworkLoggerViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
