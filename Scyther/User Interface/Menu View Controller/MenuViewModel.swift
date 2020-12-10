//
//  MVVMViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

internal struct MenuViewModel {
    /// Enum which defines each section of the ViewModel. Contains title and row data.
    enum Section: Int, CaseIterable {
        case sectionOne
        case sectionTwo

        /// String representation of the section that acts as a very short descriptor.
        var title: String? {
            switch self {
            case .sectionOne: return "Environment"
            case .sectionTwo: return "Security"
            }
        }

        /// Row definitions for each section of the ViewModel.
        var rows: [Row] {
            switch self {
            case .sectionOne: return [.envFeatureFlags, .envUserDefaults, .envServerConfig]
            case .sectionTwo: return [.envKeychain]
            }
        }
    }

    /// Enum which defines all the possible different row styles for the ViewModel.
    enum RowStyle: String {
        case `default`
        case subtitle
        case deviceHeader
        case action
    }

    /// Enum which defines all the rows for the ViewModel.
    enum Row: Int, CaseIterable {
        case envServerConfig
        case envFeatureFlags
        case envUserDefaults
        case envKeychain

        /// String representation of the section that acts as a very short descriptor.
        var title: String {
            switch self {
            case .envServerConfig: return "Server Configuration"
            case .envFeatureFlags: return "Feature Flags"
            case .envUserDefaults: return "User defaults"
            case .envKeychain: return "Keychain"
            }
        }

        /// String representation of the section that acts as a long descriptor.
        var detailTitle: String? {
            switch self {
            default: return nil
            }
        }

        /// Remote image URL that acts as an accessory for the row. Takes priority over `icon`.
        var iconURL: URL? {
            switch self {
            default: return nil
            }
        }

        /// Local image file that acts as an icon for the row
        @available(iOS 13.0, *)
        var icon: UIImage? {
            switch self {
            case .envUserDefaults: return UIImage(systemName: "gear")
            case .envKeychain: return UIImage(systemName: "key")
            case .envFeatureFlags: return UIImage(systemName: "switch.2")
            case .envServerConfig: return UIImage(systemName: "externaldrive.badge.wifi")
            }
        }

        /// Determines the visual display style of the row
        var style: RowStyle {
            switch self {
            default: return .default
            }
        }

        /// Determines the ViewController that will be presented/pushed when the row is touched/tapped.
        var detailActionController: UIViewController? {
            switch self {
            case .envFeatureFlags:
                let viewModel: FeatureFlagsViewModel = FeatureFlagsViewModel()
                let viewController: FeatureFlagsViewController = FeatureFlagsViewController()
                viewController.configure(with: viewModel)
                return viewController
            default: return nil
            }
        }

        /// Action block for the row.
        func performAction() {
            switch self {
//            case .devClearLaunchCache: UIApplication.shared.clearLaunchScreenCache()
            default: break
            }
        }

        /// Boolean value that can be used to hide certain rows. Useful for conditionally showing items.
        var isHidden: Bool {
            switch self {
            default: return false
            }
        }
    }

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
        guard rows.indices.contains(indexPath.row) else { return nil }
        return rows[indexPath.row]
    }

    func title(for row: Row, indexPath: IndexPath) -> String? {
        return row.title
    }

    func performAction(for row: Row, indexPath: IndexPath) {
        row.performAction()
    }

    // MARK: - Private data accessors
    private func section(for index: Int) -> Section? {
        return Section(rawValue: index)
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
