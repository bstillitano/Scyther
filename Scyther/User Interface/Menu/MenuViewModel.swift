//
//  MenuViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

internal protocol MenuViewModelProtocol: class {
    func viewModelShouldReloadData()
    func viewModel(viewModel: MenuViewModel?, shouldShowViewController viewController: UIViewController?)
}

internal class MenuViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: MenuViewModelProtocol?

    func actionRow(name: String, icon: UIImage?, actionController: UIViewController?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.image = icon
        row.style = .default
        row.accessoryType = actionController == nil ? UITableViewCell.AccessoryType.none : .disclosureIndicator
        row.actionBlock = { [weak self] in
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: actionController)
        }
        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Environment Section
        var environmentSection: Section = Section()
        environmentSection.title = "Environment"
        environmentSection.rows.append(actionRow(name: "Feature Flags",
                                                 icon: UIImage(systemName: "flag.fill"),
                                                 actionController: FeatureFlagsViewController()))
        environmentSection.rows.append(actionRow(name: "Server Configuration",
                                                 icon: UIImage(systemName: "icloud.fill"),
                                                 actionController: ServerConfigurationViewController()))

        //Setup Toggles Section
        var togglesSection: Section = Section()
        togglesSection.title = "Security"

        //Setup Data
        sections.append(environmentSection)
        sections.append(togglesSection)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension MenuViewModel {
    var title: String {
        return "Scyther"
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
extension MenuViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
