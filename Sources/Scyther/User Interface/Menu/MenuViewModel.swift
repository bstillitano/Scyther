//
//  MenuViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

#if !os(macOS)
import UIKit

internal protocol MenuViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
    func viewModel(viewModel: MenuViewModel?, shouldShowViewController viewController: UIViewController?)
}

internal class MenuViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: MenuViewModelProtocol?

    func actionRow(name: String, icon: UIImage?, actionBlock: ActionBlock? = nil) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.image = icon
        row.style = .default
        row.accessoryType = actionBlock == nil ? UITableViewCell.AccessoryType.none : .disclosureIndicator
        row.actionBlock = actionBlock
        return row
    }

    func headerRow(name: String, value: String?, image: UIImage? = nil) -> DeviceRow {
        let row: DeviceRow = DeviceRow()
        row.text = name
        row.detailText = value
        row.image = image
        row.style = .deviceHeader
        row.accessoryType = UITableViewCell.AccessoryType.none
        return row
    }

    func valueRow(name: String, value: String?, icon: UIImage?, showMenu: Bool = false) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value
        row.image = icon
        row.style = .default
        row.shouldShowMenuForRow = showMenu
        row.accessoryType = UITableViewCell.AccessoryType.none
        return row
    }

    /// Empty row that contains text in a 'disabled' style
    func emptyRow(text: String) -> EmptyRow {
        var row: EmptyRow = EmptyRow()
        row.text = text

        return row
    }

    /// Switch to enable/disable showing view frames
    var viewFramesSwitch: SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Show View Frames"
        row.image = UIImage(systemImage: "viewfinder")

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = InterfaceToolkit.instance.showsViewBorders
        switchView.actionBlock = {
            InterfaceToolkit.instance.swizzleLayout()
            InterfaceToolkit.instance.showsViewBorders = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

        return row
    }

    /// Switch to enable/disable slow animations
    var slowAnimationsSwitch: SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Slow Animations"
        row.image = UIImage(systemImage: "tortoise")

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = InterfaceToolkit.instance.slowAnimationsEnabled
        switchView.actionBlock = { [weak self] in
            InterfaceToolkit.instance.slowAnimationsEnabled = switchView.isOn
            self?.delegate?.viewModelShouldReloadData()
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

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
                                            image: .appIcon))
        deviceSection.rows.append(valueRow(name: "Version",
                                           value: UIDevice.current.systemVersion,
                                           icon: nil))
        deviceSection.rows.append(valueRow(name: "Hardware",
                                           value: UIDevice.current.modelName,
                                           icon: nil))
        deviceSection.rows.append(valueRow(name: "UDID",
                                           value: UIDevice.current.identifierForVendor?.uuidString,
                                           icon: nil,
                                           showMenu: true))
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
                                                value: AppEnvironment.configuration().rawValue,
                                                icon: nil))
        applicationSection.rows.append(valueRow(name: "Build Date",
                                                value: Bundle.main.buildDate.formatted(),
                                                icon: nil))

        /// Setup Networking Section
        var networkSection: Section = Section()
        networkSection.title = "Networking"
        networkSection.rows.append(valueRow(name: "IP Address",
                                            value: Scyther.logger.ipAddress,
                                            icon: UIImage(systemImage: "network")))
        networkSection.rows.append(actionRow(name: "Network Logs",
                                             icon: UIImage(systemImage: "doc.append"),
                                             actionBlock: { [weak self] in
                                                 self?.delegate?.viewModel(viewModel: self, shouldShowViewController: NetworkLoggerViewController())
                                             }))
        networkSection.rows.append(actionRow(name: "Server Configuration",
                                             icon: UIImage(systemImage: "externaldrive.badge.icloud"),
                                             actionBlock: { [weak self] in
                                                 self?.delegate?.viewModel(viewModel: self, shouldShowViewController: ServerConfigurationViewController())
                                             }))

        /// Setup Environment Section
        var environmentSection: Section = Section()
        environmentSection.title = "Data"
        environmentSection.rows.append(actionRow(name: "Feature Flags",
                                                 icon: UIImage(systemImage: "flag"),
                                                 actionBlock: { [weak self] in
                                                     self?.delegate?.viewModel(viewModel: self, shouldShowViewController: FeatureFlagsViewController())
                                                 }))
        environmentSection.rows.append(actionRow(name: "User Defaults",
                                                 icon: UIImage(systemImage: "face.dashed"),
                                                 actionBlock: { [weak self] in
                                                     self?.delegate?.viewModel(viewModel: self, shouldShowViewController: UserDefaultsViewController())
                                                 }))
        environmentSection.rows.append(actionRow(name: "Cookies",
                                                 icon: UIImage(systemImage: "info.circle"),
                                                 actionBlock: { [weak self] in
                                                     self?.delegate?.viewModel(viewModel: self, shouldShowViewController: CookieBrowserViewController())
                                                 }))

        /// Setup Security Section
        var securitySection: Section = Section()
        securitySection.title = "Security"
        securitySection.rows.append(actionRow(name: "Keychain Browser",
                                              icon: UIImage(systemImage: "key"),
                                              actionBlock: { [weak self] in
                                                  self?.delegate?.viewModel(viewModel: self, shouldShowViewController: DataBrowserViewController(data: KeychainBrowser.keychainItems))
                                              }))

        /// Setup Support Section
        var systemSection: Section = Section()
        systemSection.title = "System Tools"
        systemSection.rows.append(actionRow(name: "Location Spoofer",
                                             icon: UIImage(systemImage: "location.circle"),
                                             actionBlock: { [weak self] in
                                                 self?.delegate?.viewModel(viewModel: self, shouldShowViewController: LocationSpooferViewController())
                                             }))
        systemSection.rows.append(emptyRow(text: "More coming soon"))

        /// Setup Notifications Section
        var notificationsSection: Section = Section()
        notificationsSection.title = "Notifications"
        notificationsSection.rows.append(actionRow(name: "Notification Logger",
                                                   icon: UIImage(systemImage: "list.bullet"),
                                                   actionBlock: { [weak self] in
                                                       self?.delegate?.viewModel(viewModel: self, shouldShowViewController: NotificationLoggerViewController())
                                                   }))
        notificationsSection.rows.append(actionRow(name: "Notification Tester",
                                                   icon: UIImage(systemImage: "bell"),
                                                   actionBlock: { [weak self] in
                                                       self?.delegate?.viewModel(viewModel: self, shouldShowViewController: NotificationTesterViewController())
                                                   }))
        notificationsSection.rows.append(valueRow(name: "APNS Token",
                                                  value: Scyther.instance.apnsToken ?? "Not set",
                                                  icon: UIImage(systemImage: "applelogo"),
                                                  showMenu: true))
        notificationsSection.rows.append(valueRow(name: "FCM Token",
                                                  value: Scyther.instance.fcmToken ?? "Not set",
                                                  icon: UIImage(systemImage: "flame"),
                                                  showMenu: true))

        /// Setup UI/UX Section
        var uiUxSection: Section = Section()
        uiUxSection.title = "UI/UX"
        uiUxSection.rows.append(actionRow(name: "Fonts",
                                          icon: UIImage(systemImage: "textformat"),
                                          actionBlock: { [weak self] in
                                              self?.delegate?.viewModel(viewModel: self, shouldShowViewController: FontsViewController())
                                          }))
        uiUxSection.rows.append(actionRow(name: "Interface Components",
                                          icon: UIImage(systemImage: "apps.iphone"),
                                          actionBlock: { [weak self] in
                                              self?.delegate?.viewModel(viewModel: self, shouldShowViewController: InterfacePreviewsViewController())
                                          }))
        uiUxSection.rows.append(actionRow(name: "Grid Overlay",
                                          icon: UIImage(systemImage: "rectangle.split.3x3"),
                                          actionBlock: { [weak self] in
                                              self?.delegate?.viewModel(viewModel: self, shouldShowViewController: GridOverlayViewController())
                                          }))
        uiUxSection.rows.append(actionRow(name: "Touch Visualiser",
                                          icon: UIImage(systemImage: "hand.point.up"),
                                          actionBlock: { [weak self] in
                                              self?.delegate?.viewModel(viewModel: self, shouldShowViewController: TouchVisualiserViewController())
                                          }))
        uiUxSection.rows.append(viewFramesSwitch)
        uiUxSection.rows.append(slowAnimationsSwitch)

        /// Setup Development Section
        var developmentSection: Section = Section()
        developmentSection.title = "Development Tools"
        if Scyther.instance.developerOptions.isEmpty {
            developmentSection.rows.append(emptyRow(text: "No tools configured"))
        } else {
            for tool: DeveloperOption in Scyther.instance.developerOptions {
                developmentSection.rows.append(actionRow(name: tool.name ?? "",
                                                         icon: tool.icon,
                                                         actionBlock: { [weak self] in
                                                             self?.delegate?.viewModel(viewModel: self, shouldShowViewController: tool.viewController)
                                                         }))
            }
        }

        /// Setup Data
        sections.append(deviceSection)
        sections.append(applicationSection)
        sections.append(networkSection)
        sections.append(environmentSection)
        sections.append(securitySection)
        sections.append(systemSection)
        sections.append(notificationsSection)
        sections.append(uiUxSection)
        sections.append(developmentSection)

        /// Call Delegate
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
extension MenuViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}

extension MenuViewModel {
    @objc
    func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
}
#endif
