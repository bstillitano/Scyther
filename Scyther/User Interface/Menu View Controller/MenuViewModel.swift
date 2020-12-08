//
//  MenuViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

import UIKit
import Security
import Foundation

internal struct MenuViewModel {
    enum Section: Int, CaseIterable {
//        case device
//        case application
        case environment
//        case support
//        case developmentTools

        var title: String? {
            switch self {
//            case .device: return nil
//            case .application: return "Application"
            case .environment: return "Environment"
//            case .support: return "Support"
//            case .developmentTools: return "Development Tools"
            }
        }

        var rows: [Row] {
            switch self {
//            case .device: return [.deviceGraphic, .deviceVersion, .deviceHardware]
//            case .application: return [.appVersion, .appProcessID, .appReleaseType, .appBuildDate, (Entitlements.current != nil) ? .appEntitlements : nil, (ProvisioningProfile.embedded != nil) ? .appProvisioningProfile : nil].compactMap { $0 }
//            case .environment: return [.envServerConfig, .envFeatureFlags, .envKeychain, .envUserDefaults]
            case .environment: return [.envFeatureFlags]
//            case .support: return [.supportExportLogs]
//            case .developmentTools: return [.devConsoleLog, .devNetworkInspector, .devClearLaunchCache]
            }
        }
    }

    enum RowStyle: String {
        case `default`
        case subtitle
        case deviceHeader
        case action
    }

    enum Row: Int, CaseIterable {
        // Device section
        case deviceGraphic
        case deviceVersion
        case deviceHardware
        case deviceSystemLog

        // Application section
        case appVersion
        case appProcessID
        case appReleaseType
        case appBuildDate
        case appEntitlements
        case appProvisioningProfile
        case appBinaryBundle
        case appDataBundle

        // Enviroment
        case envServerConfig
        case envFeatureFlags
        case envUserDefaults
        case envKeychain

        // Support
        case supportExportLogs

        // Developer extras
        case devClearLaunchCache
        case devConsoleLog
        case devNetworkInspector
        case devCustomRow

        // Title
        var title: String {
            switch self {
//            case .deviceGraphic: return (MobileGestalt.copyAnswer(.userAsignedDeviceName) ?? MobileDevices.current?.identifier) ?? ""
            case .deviceGraphic: return "GRAPHIC PLACEHOLDER"
            case .deviceVersion: return "Version"
            case .deviceHardware: return "Hardware"
            case .deviceSystemLog: return "System Log"

            case .appVersion: return "Version"
            case .appProcessID: return "Process ID"
            case .appReleaseType: return "Release type"
            case .appBuildDate: return "Build date"
            case .appEntitlements: return "Entitlements"
            case .appProvisioningProfile: return "Provisioning Profile"
            case .appBinaryBundle: return "App Bundle"
            case .appDataBundle: return "Data Bundle"

            case .envServerConfig: return "Server Configuration"
            case .envFeatureFlags: return "Feature Flags"
            case .envUserDefaults: return "User defaults"
            case .envKeychain: return "Keychain"

            case .supportExportLogs: return "Export logs & device profile"

            case .devCustomRow: return "" // Not used
            case .devConsoleLog: return "Console log"
            case .devClearLaunchCache: return "Clear launch screen cache"
            case .devNetworkInspector: return "Network Interceptor"
            }
        }

        var detailTitle: String? {
            switch self {
//            case .deviceGraphic: return [MobileDevices.current?.description, MobileGestalt.copyAnswer(.hardwarePlatform)].compactMap { $0 }.joined(separator: " - ")
//            case .deviceVersion: return "\(UIDevice.current.productVersion ?? "unknown") (\(UIDevice.current.buildVersion ?? "uknown"))"
//            case .deviceHardware: return "\(UIDevice.current.hardwareModel ?? "unknown") (\(UIDevice.current.modelNumber ?? "unknown"))"
//            case .appVersion: return "\(UIApplication.shared.releaseVersion) (\(UIApplication.shared.buildVersion))"
//            case .appProcessID: return "\(ProcessInfo.processInfo.processIdentifier)"
//            case .appBuildDate: return UIApplication.shared.buildDateString ?? "unknown"
//            case .appReleaseType: return UIApplication.shared.releaseType
//            case .appDataBundle: return UIApplication.shared.dataBundlePath ?? "uknown"
//            case .appBinaryBundle: return UIApplication.shared.appBundlePath ?? "unknown"
            default: return nil
            }
        }

        var iconURL: URL? {
            switch self {
//            case .deviceGraphic: return MobileDevices.current?.iconURL
            default: return nil
            }
        }

        @available(iOS 13.0, *)
        var icon: UIImage? {
            switch self {
            case .devConsoleLog: return UIImage(systemName: "exclamationmark.triangle")
            case .devNetworkInspector: return UIImage(systemName: "arrow.up.arrow.down")
            case .appEntitlements: return UIImage(systemName: "lock.shield")
            case .appProvisioningProfile: return UIImage(systemName: "doc.plaintext")
            case .envUserDefaults: return UIImage(systemName: "gear")
            case .envKeychain: return UIImage(systemName: "key")
            case .envFeatureFlags: return UIImage(systemName: "switch.2")
            case .envServerConfig: return UIImage(systemName: "externaldrive.badge.wifi")
            default: return nil
            }
        }

        var style: RowStyle {
            switch self {
            case .deviceGraphic: return .deviceHeader
            case .appBinaryBundle, .appDataBundle: return .subtitle
            case .deviceSystemLog, .devClearLaunchCache, .supportExportLogs: return .action
            case .devCustomRow: return .action
            default: return .default
            }
        }

        var detailActionController: UIViewController? {
            switch self {
//            case .deviceGraphic: if #available(iOS 13.0, *) { return MobileDeviceViewController() } else { return nil }
            case .envServerConfig, .envFeatureFlags: return UIViewController()
//            case .appEntitlements:
//                guard let viewModel = Entitlements.current?.dataBrowserViewModel else { return nil }
//                let controller = DataBrowserTableViewController()
//                controller.configure(with: viewModel)
//                return controller
//
//            case .appProvisioningProfile:
//                guard let viewModel = ProvisioningProfile.embedded?.dataBrowserViewModel else { return nil }
//                let controller = DataBrowserTableViewController()
//                controller.configure(with: viewModel)
//                return controller
//
//            case .envUserDefaults:
//                let controller = DataBrowserTableViewController()
//                controller.configure(with: DataBrowserTableViewModel(title: title, data: UserDefaults.standard.dictionaryRepresentation() as [String: AnyObject]))
//                return controller
//
//            case .envKeychain:
//                let controller = DataBrowserTableViewController()
//                controller.configure(with: DataBrowserTableViewModel(title: title, data: KeychainItems.keychainItems()))
//                return controller
//
//            case .devConsoleLog: return ConsoleLogViewController()
//            case .devNetworkInspector: if #available(iOS 13.0, *) { return NetworkRequestsViewController() } else { return nil }
            default: return nil
            }
        }

        func performAction() {
            switch self {
//            case .devClearLaunchCache: UIApplication.shared.clearLaunchScreenCache()
            default: break
            }
        }

        var isHidden: Bool {
            switch self {
            case .appProcessID: return true
            case .appEntitlements: return true
            case .envUserDefaults: return true
            case .envKeychain: return true
            case .appProvisioningProfile: return true
            case .devClearLaunchCache: return true
            default: return false
            }
        }
    }

    // MARK: - Network & feature flag controllers
    var networkController: UIViewController?

    var featureFlagController: UIViewController?

    // MARK: - Public data accessors
    var title: String {
        return "Scyther"
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

    internal func row(at indexPath: IndexPath) -> Row? {
        guard let rows = rows(inSection: indexPath.section) else { return nil }
        guard rows.indices.contains(indexPath.row) else { return nil}
        return rows[indexPath.row]
    }

    func title(for row: Row, indexPath: IndexPath) -> String? {
        if case .devCustomRow = row {
//            let nonActionEntriesCount = nonActionRows(inSection: Section.developmentTools.rawValue)?.count ?? 0
//            return InternalMenu.default.customDebugActions[indexPath.row - nonActionEntriesCount].title
            return nil
        } else {
            return row.title
        }
    }

    func performAction(for row: Row, indexPath: IndexPath) {
        if case .devCustomRow = row {
//            let nonActionEntriesCount = nonActionRows(inSection: Section.developmentTools.rawValue)?.count ?? 0
//            InternalMenu.default.customDebugActions[indexPath.row - nonActionEntriesCount].actionBlock()
        } else {
            return row.performAction()
        }
    }

    // MARK: - Private data accessors
    private func section(for index: Int) -> Section? {
        return Section(rawValue: index)
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }

        var rows = section.rows
//        if case .developmentTools = section {
//            let nonActionEntries = nonActionRows(inSection: index) ?? []
////            let custom = InternalMenu.default.customDebugActions
//            let customRows = custom.compactMap { _ in Row.devCustomRow }
//            rows = nonActionEntries + customRows + rows.filter { ($0.style == .action) }
//        }
        return rows.filter { !$0.isHidden }
    }

    private func nonActionRows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }

        var rows = section.rows
//        if case .developmentTools = section {
//            let custom = InternalMenu.default.customDebugActions
//            let customRows = custom.compactMap { _ in Row.devCustomRow }
//            rows = customRows + rows
//        }
        return rows.filter { !$0.isHidden }.filter { ($0.style != .action) }
    }

}

struct KeychainItems {

    static func keychainItems() -> [String: [String: AnyObject]] {
        [
            "Generic Passwords": Self.keychainItems(ofClass: kSecClassGenericPassword),
            "Internet Passwords": Self.keychainItems(ofClass: kSecClassInternetPassword),
            "Identities": Self.keychainItems(ofClass: kSecClassIdentity)
        ]
    }

    static private func keychainItems(ofClass secClass: CFString) -> [String: AnyObject] {
        let query: [String: Any] = [
            kSecClass as String: secClass,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let lastResultCode = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0))
        }

        //  this also works, although I am not sure if it is as save as calling withUnsafeMutabePointer
        //  let lastResultCode = SecItemCopyMatching(query as CFDictionary, &result)
        var values = [String: AnyObject]()
        if lastResultCode == noErr, let array = result as? Array<Dictionary<String, Any>> {
            array.forEach {
                if let key = $0[kSecAttrAccount as String] as? String, let value = $0[kSecValueData as String] as? Data {
                    values[key] = String(data: value, encoding: .utf8) as AnyObject?
                }
                else if let key = $0[kSecAttrLabel as String] as? String, let value = $0[kSecValueRef as String] {
                    values[key] = value as AnyObject
                }
            }
        }
        return values
    }
}
