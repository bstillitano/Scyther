//
//  MenuViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

#if !os(macOS)
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

    func headerRow(name: String, value: String?, iconURL: URL? = nil) -> DeviceRow {
        let row: DeviceRow = DeviceRow()
        row.text = name
        row.detailText = value
        row.imageURL = iconURL
        row.style = .deviceHeader
        row.accessoryType = UITableViewCell.AccessoryType.none
        return row
    }

    func valueRow(name: String, value: String?, icon: UIImage?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value
        row.image = icon
        row.style = .default
        row.accessoryType = UITableViewCell.AccessoryType.none
        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Device Section
        var deviceSection: Section = Section()
        deviceSection.title = "Device"
        deviceSection.rows.append(headerRow(name: UIDevice.current.name,
                                            value: UIDevice.current.model,
                                            iconURL: UIDevice.current.deviceIconURL))
        deviceSection.rows.append(valueRow(name: "Version",
                                           value: UIDevice.current.systemVersion,
                                           icon: nil))
        deviceSection.rows.append(valueRow(name: "Hardware",
                                           value: UIDevice.current.modelName,
                                           icon: nil))
        //Setup Application Section
        var applicationSection: Section = Section()
        applicationSection.title = "Application"
        applicationSection.rows.append(valueRow(name: "Bundle Identifier",
                                                value: Bundle.main.bundleIdentifier,
                                                icon: nil))
        applicationSection.rows.append(valueRow(name: "Version",
                                                value: Bundle.main.versionNumber,
                                                icon: nil))
        applicationSection.rows.append(valueRow(name: "Build Number",
                                                value: Bundle.main.buildNumber,
                                                icon: nil))
        applicationSection.rows.append(valueRow(name: "Process ID",
                                                value: String(getpid()),
                                                icon: nil))
        applicationSection.rows.append(valueRow(name: "Release Type",
                                                value: EnvironmentReader.configuration().rawValue,
                                                icon: nil))
        applicationSection.rows.append(valueRow(name: "Build Date",
                                                value: Bundle.main.buildDate.formatted(),
                                                icon: nil))

        //Setup Environment Section
        var environmentSection: Section = Section()
        environmentSection.title = "Environment"
        environmentSection.rows.append(actionRow(name: "Feature Flags",
                                                 icon: UIImage(systemImage: "flag"),
                                                 actionController: FeatureFlagsViewController()))
        environmentSection.rows.append(actionRow(name: "Server Configuration",
                                                 icon: UIImage(systemImage: "externaldrive.badge.icloud"),
                                                 actionController: ServerConfigurationViewController()))
        environmentSection.rows.append(actionRow(name: "User Defaults",
                                                 icon: UIImage(systemImage: "face.dashed"),
                                                 actionController: UserDefaultsViewController()))

        //Setup Security Section
        var securitySection: Section = Section()
        securitySection.title = "Security"

        //Setup Support Section
        var supportSection: Section = Section()
        supportSection.title = "Support"

        //Setup Development Section
        var developmentSection: Section = Section()
        developmentSection.title = "Development Tools"

        //Setup Data
        sections.append(deviceSection)
        sections.append(applicationSection)
        sections.append(environmentSection)
        sections.append(securitySection)
        sections.append(supportSection)
        sections.append(developmentSection)

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
#endif
