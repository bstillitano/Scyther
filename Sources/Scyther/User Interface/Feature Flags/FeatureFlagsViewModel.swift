//
//  FFViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

#if !os(macOS)
import UIKit

internal protocol FeatureFlagsViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
}

internal class FeatureFlagsViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: FeatureFlagsViewModelProtocol?

    /// Global overrides switch object. Controls whether overrides are respected or not.
    var enableOverrrides: SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Enable overrides"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = Toggler.instance.localOverridesEnabled
        switchView.actionBlock = {
            Toggler.instance.localOverridesEnabled = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

        return row
    }

    /// Button item that allows the caller to restore all `Toggle` values to their remote value
    var restoreDefaults: ButtonRow {
        //Setup Row
        var row: ButtonRow = ButtonRow()
        row.text = "Restore remote values"
        row.actionBlock = {[weak self] in
            for toggle: Toggle in Toggler.instance.toggles {
                Toggler.instance.setLocalValue(value: toggle.remoteValue, forToggleWithName: toggle.name)
            }
            self?.prepareObjects()
        }
        return row
    }

    /// Single toggle override switch object. Controls what value should be returned by the override.
    func toggleSwitch(for name: String) -> SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = name
        row.detailText = "Remote value: \(Toggler.instance.remoteValue(forToggle: name).stringValue)"
        // Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = Toggler.instance.localValue(forToggle: name)
        switchView.actionBlock = {
            Toggler.instance.setLocalValue(value: switchView.isOn, forToggleWithName: name)
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

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

        //Setup Global Section
        var globalSection: Section = Section()
        globalSection.title = "Global Settings"
        globalSection.rows = [enableOverrrides, restoreDefaults]

        //Setup Toggles Section
        var togglesSection: Section = Section()
        togglesSection.title = "Toggles"
        togglesSection.rows = Toggler.instance.toggles.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
            .map({ toggleSwitch(for: $0.name) })
        if togglesSection.rows.isEmpty {
            togglesSection.rows.append(emptyRow(text: "No toggles configured"))
        }

        //Setup Data
        sections.append(globalSection)
        sections.append(togglesSection)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension FeatureFlagsViewModel {
    var title: String {
        return "Feature Flags"
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
extension FeatureFlagsViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}


extension FeatureFlagsViewModel {
    @objc
    func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
}
#endif
