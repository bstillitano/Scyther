//
//  FFViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

internal class FFViewModel {
    static var enableOverrrides: SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Enable overrides"
        row.switchView.isOn = Toggler.instance.localOverridesEnabled
        row.switchView.addTarget(nil, action: #selector(switchAction(_:)), for: .valueChanged)
        return row
    }
    
    static func toggleSwitch(for name: String) -> SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = name
        row.switchView.addTarget(nil, action: #selector(switchAction(_:)), for: .valueChanged)
        return row
    }
    
    /// Enum which defines each section of the ViewModel. Contains title and row data.
    enum Section: Int, CaseIterable {
        case globalSettings
        case toggles

        /// String representation of the section that acts as a very short descriptor.
        var title: String? {
            switch self {
            case .globalSettings: return "Global Settings"
            case .toggles: return "Toggles"
            }
        }

        /// Row definitions for each section of the ViewModel.
        var rows: [SwitchAccessoryRow] {
            // Setup Switch
            switch self {
            case .globalSettings: return [enableOverrrides]
            case .toggles: return Toggler.instance.toggles.map( { toggleSwitch(for: $0.name) } )
            }
        }
    }

    // MARK: - Public data accessors
    var title: String {
        return "Feature Flags"
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

    internal func row(at indexPath: IndexPath) -> SwitchAccessoryRow? {
        guard let rows = rows(inSection: indexPath.section) else { return nil }
        guard rows.indices.contains(indexPath.row) else { return nil }
        return rows[indexPath.row]
    }

    func title(for row: SwitchAccessoryRow, indexPath: IndexPath) -> String? {
        return row.text
    }

    func performAction(for row: SwitchAccessoryRow, indexPath: IndexPath) {
        row.actionBlock?()
    }

    // MARK: - Private data accessors
    private func section(for index: Int) -> Section? {
        return Section(rawValue: index)
    }

    private func rows(inSection index: Int) -> [SwitchAccessoryRow]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}

extension FFViewModel {
    @objc
    func switchAction(_ sender: UISwitch) {
        Toggler.instance.setLocalValue(value: sender.isOn, forToggleWithName: sender.title ?? "")
    }
}
