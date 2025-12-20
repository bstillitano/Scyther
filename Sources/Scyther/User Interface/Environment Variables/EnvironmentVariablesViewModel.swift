//
//  EnvironmentVariablesViewModel.swift
//
//
//  Created by Brandon Stillitano on 14/4/2022.
//

#if !os(macOS)
import UIKit

internal protocol EnvironmentVariablesViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
}

internal class EnvironmentVariablesViewModel {
    // MARK: - Data
    private var sections: [TableSection] = []

    // MARK: - Delegate
    weak var delegate: EnvironmentVariablesViewModelProtocol?

    /// Single row representing a single environment variable
    func environmentVariable(name: String, value: String) -> SubtitleRow {
        let row: SubtitleRow = SubtitleRow()
        row.text = name
        row.detailText = value
        return row
    }

    /// Empty row that contains text in a 'disabled' style
    func emptyRow(text: String) -> EmptyRow {
        var row: EmptyRow = EmptyRow()
        row.text = text
        return row
    }

    func prepareObjects() {
        // Clear Data
        sections.removeAll()

        // Setup Custom Variables Section
        var variablesSection: TableSection = TableSection()
        variablesSection.title = "Custom Key/Values"
        variablesSection.rows = Scyther.instance.customEnvironmentVariables
            .sorted { $0.key < $1.key }
            .map { environmentVariable(name: $0.key, value: $0.value) }
        if variablesSection.rows.isEmpty {
            variablesSection.rows.append(emptyRow(text: "No variables configured"))
        }

        sections.append(variablesSection)

        // Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension EnvironmentVariablesViewModel {
    var title: String {
        return "Environment Variables"
    }

    var numberOfSections: Int {
        return sections.count
    }

    func title(forSection index: Int) -> String? {
        return sections[index].title
    }

    func numberOfRows(inSection index: Int) -> Int {
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
extension EnvironmentVariablesViewModel {
    private func section(for index: Int) -> TableSection? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
