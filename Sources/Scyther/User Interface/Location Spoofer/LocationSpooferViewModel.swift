//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import UIKit

internal protocol LocationSpooferViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
}

internal class LocationSpooferViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: LocationSpooferViewModelProtocol?

    /// Switch to enable/disable location spoofing
    var enableSpoofingSwitch: SwitchAccessoryRow {
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Enable location spoofing"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = InterfaceToolkit.instance.visualiseTouches
        switchView.actionBlock = { [weak self] in
            LocationSpoofer.instance.spoofingEnabled = switchView.isOn
            self?.prepareObjects()
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView
        return row
    }

    func locationRow(for location: Location) -> DefaultRow {
        let value: DefaultRow = DefaultRow()
        value.text = location.name.capitalized
        value.accessoryType = LocationSpoofer.instance.spoofedLocation == location ? .checkmark : .none
        value.actionBlock = { [weak self] in
            LocationSpoofer.instance.spoofedLocation = location
            self?.prepareObjects()
        }
        return value
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Spoofing Section
        var enabledSection: Section = Section()
        enabledSection.title = "Location Spoofing"
        enabledSection.rows.append(enableSpoofingSwitch)

        //Setup Locations Section
        var locationsSection: Section = Section()
        locationsSection.title = "Locations"
        LocationSpoofer.instance.presetLocations.sorted(by: { $0.name < $1.name }).forEach { location in
            locationsSection.rows.append(locationRow(for: location))
        }

        //Setup Data
        sections.append(enabledSection)
        if LocationSpoofer.instance.spoofingEnabled {
            sections.append(locationsSection)
        }

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension LocationSpooferViewModel {
    var title: String {
        return "Location Spoofer"
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
extension LocationSpooferViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}

extension LocationSpooferViewModel {
    @objc
    func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
}
