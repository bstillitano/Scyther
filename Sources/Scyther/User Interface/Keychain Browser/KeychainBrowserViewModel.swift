//
//  File.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

#if !os(macOS)
import UIKit

internal protocol KeychainBrowserViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
    func viewModel(viewModel: KeychainBrowserViewModel?, shouldShowViewController viewController: UIViewController?)
}

internal class KeychainBrowserViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: KeychainBrowserViewModelProtocol?

    /// Single row representing a single value and key
    func actionRow(title: String?, actionBlock: ActionBlock? = nil) -> ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = title
        row.actionBlock = actionBlock
        row.accessoryType = .none
        return row
    }

    /// Empty row that contains text in a 'disabled' style
    func emptyRow(text: String) -> EmptyRow {
        var row: EmptyRow = EmptyRow()
        row.text = text

        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Sections
        for kSecClassType in KeychainBrowser.keychainItems {
            var section: Section = Section()
            section.title = kSecClassType.key
            section.rows.append(actionRow(title: kSecClassType.key, actionBlock: { [weak self] in
                self?.delegate?.viewModel(viewModel: self, shouldShowViewController: DataBrowserViewController(data: KeychainBrowser.keychainItems[kSecClassType.key] ?? [:]))
            }))
            if section.rows.isEmpty {
                section.rows.append(emptyRow(text: "No \(kSecClassType.key.lowercased()) in keychain"))
            }
            sections.append(section)
        }

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension KeychainBrowserViewModel {
    var title: String {
        return "Keychain Browser"
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
extension KeychainBrowserViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
