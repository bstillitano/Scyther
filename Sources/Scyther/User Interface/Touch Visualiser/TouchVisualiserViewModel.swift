//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import UIKit

internal protocol TouchVisualiserViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
}

internal class TouchVisualiserViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: TouchVisualiserViewModelProtocol?

    /// Switch to enable/disable touch visualiser
    var visualiseTouchesSwitch: SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Show screen touches"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = InterfaceToolkit.instance.visualiseTouches
        switchView.actionBlock = { [weak self] in
            InterfaceToolkit.instance.visualiseTouches = switchView.isOn
            self?.delegate?.viewModelShouldReloadData()
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView
        return row
    }
    
    var touchDurationSwitch: SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Show touch duration"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = InterfaceToolkit.instance.visualiseTouches
        switchView.actionBlock = {
            InterfaceToolkit.instance.touchVisualiser.config.showsTouchDuration = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView
        return row
    }
    
    var touchRadiusSwitch: SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Show touch radius"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = InterfaceToolkit.instance.visualiseTouches
        switchView.actionBlock = {
            InterfaceToolkit.instance.touchVisualiser.config.showsTouchRadius = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView
        return row
    }
    
    var touchLoggingSwitch: SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Log screen touches"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = InterfaceToolkit.instance.visualiseTouches
        switchView.actionBlock = {
            InterfaceToolkit.instance.touchVisualiser.config.loggingEnabled = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView
        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Section
        var section: Section = Section()
        section.rows.append(visualiseTouchesSwitch)
        if InterfaceToolkit.instance.visualiseTouches {
            section.rows.append(touchDurationSwitch)
            section.rows.append(touchRadiusSwitch)
            section.rows.append(touchLoggingSwitch)
        }

        //Setup Data
        sections.append(section)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension TouchVisualiserViewModel {
    var title: String {
        return "Visualise Touches"
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
extension TouchVisualiserViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}

extension TouchVisualiserViewModel {
    @objc
    func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
}
