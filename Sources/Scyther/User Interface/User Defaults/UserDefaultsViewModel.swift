//
//  UserDefaultsViewModel.swift
//  
//
//  Created by Brandon Stillitano on 18/12/20.
//

#if !os(macOS)
import UIKit

internal protocol UserDefaultsViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class UserDefaultsViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: UserDefaultsViewModelProtocol?

    /// Single row representing a single environment variable
    func defaultRow(name: String, value: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value ?? "NaS"

        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup KeyValues Section
        let keyValues = UserDefaults.standard.stringStringDictionaryRepresentation.sorted(by: { $0.key < $1.key })
        var keyValuesSection: Section = Section()
        keyValuesSection.title = "Key/Values"
        keyValuesSection.rows = keyValues.compactMap( { defaultRow(name: $0.key, value: $0.value) })

        //Setup Data
        sections.append(keyValuesSection)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension UserDefaultsViewModel {
    var title: String {
        return "User Defaults"
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
extension UserDefaultsViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
