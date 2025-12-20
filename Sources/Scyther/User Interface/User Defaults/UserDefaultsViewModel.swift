//
//  UserDefaultsViewModel.swift
//  
//
//  Created by Brandon Stillitano on 18/12/20.
//

#if !os(macOS)
import UIKit

internal protocol UserDefaultsViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
}

internal class UserDefaultsViewModel {
    // MARK: - Data
    private var sections: [TableSection] = []

    // MARK: - Delegate
    weak var delegate: UserDefaultsViewModelProtocol?

    /// Single row representing a single user defalt
    func defaultRow(name: String, value: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value ?? "NaS"
        row.trailingSwipeActionsConfiguration = UISwipeActionsConfiguration(actions: [
            .deleteAction(withActionBlock: { [weak self] in
                UserDefaults.standard.removeObject(forKey: name)
                self?.prepareObjects()
        })
    ])
        return row
    }
    
    var clearDefaultsRow: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Reset UserDefaults.standard"
        row.actionBlock = { [weak self] in
            UserDefaults.standard.dictionaryRepresentation().keys.filter({
                !$0.lowercased().hasPrefix("scyther")
            }).forEach(UserDefaults.standard.removeObject(forKey:))
            UserDefaults.standard.synchronize()
            self?.prepareObjects()
        }

        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup KeyValues Section
        let keyValues = UserDefaults.standard.stringStringDictionaryRepresentation.sorted(by: { $0.key.lowercased() < $1.key.lowercased() })
        var keyValuesSection: TableSection = TableSection()
        keyValuesSection.title = "Key/Values"
        keyValuesSection.rows = keyValues.compactMap( { defaultRow(name: $0.key, value: $0.value) })
        
        var deleteAllSection: TableSection = TableSection()
        deleteAllSection.rows.append(clearDefaultsRow)
        deleteAllSection.footer = "This will delete all values stored inside `UserDefaults.standard`, created by your app. This will not clear any values created internally by Scyther that are used for debug/feature purposes."

        //Setup Data
        sections.append(keyValuesSection)
        sections.append(deleteAllSection)

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
    
    func footer(forSection index: Int) -> String? {
        return sections[index].footer
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
extension UserDefaultsViewModel {
    private func section(for index: Int) -> TableSection? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
