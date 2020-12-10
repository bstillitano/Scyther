//
//  FFViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

internal class FeatureFlagsViewModel {
    /// Global overrides switch object. Controls whether overrides are respected or not.
    static var enableOverrrides: SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Enable overrides"
        row.switchView.isOn = Toggler.instance.localOverridesEnabled
        row.switchView.actionBlock = {
            Toggler.instance.localOverridesEnabled = row.switchView.isOn
        }
        row.switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        return row
    }
    
    /// Single toggle override switch object. Controls what value should be returned by the override.
    static func toggleSwitch(for name: String) -> SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = name
        row.switchView.isOn = Toggler.instance.localValue(forToggle: name)
        row.switchView.actionBlock = {
            Toggler.instance.setLocalValue(value: row.switchView.isOn, forToggleWithName: name)
        }
        row.switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
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
            case .toggles: return Toggler.instance.toggles.sorted(by: { $0.name < $1.name })
                .map( { toggleSwitch(for: $0.name) } )
            }
        }
    }
}

// MARK: - Public data accessors
extension FeatureFlagsViewModel {
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

extension FeatureFlagsViewModel {
    @objc
    static func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
}
