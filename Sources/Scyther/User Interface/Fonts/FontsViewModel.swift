//
//  FontsViewModel.swift
//
//
//  Created by Brandon Stillitano on 15/2/21.
//

#if !os(macOS)
import UIKit

internal protocol FontsViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class FontsViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: FontsViewModelProtocol?

    func valueRow(font: UIFont?) -> FontRow {
        let row: FontRow = FontRow()
        row.text = font?.fontName
        row.font = font
        row.style = .font
        row.accessoryType = UITableViewCell.AccessoryType.none
        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Font Sections
        UIFont.familyNames.forEach({ familyName in
            var fontSection: Section = Section()
            fontSection.title = familyName
            fontSection.rows = UIFont.fontNames(forFamilyName: familyName).map( { valueRow(font: UIFont(name: $0, size: 16.0)) } )
            sections.append(fontSection)
        })

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension FontsViewModel {
    var title: String {
        return "Fonts"
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
extension FontsViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
