//
//  DeveloperOption.swift
//
//
//  Created by Brandon Stillitano on 12/2/21.
//

#if !os(macOS)
import UIKit

/// Defines the different types of developer options that can be displayed in the Scyther menu.
///
/// The type determines how the option is rendered and what interaction it provides.
/// This enum controls the visual representation and behavior of menu items.
///
/// ## Usage
///
/// This type is typically used internally by ``DeveloperOption`` to determine
/// how to display and handle user interaction with menu items.
public enum DeveloperOptionType: CaseIterable {
    /// A developer option that opens a view controller when tapped.
    ///
    /// Use this type for options that require a full screen interface, such as:
    /// - Settings panels
    /// - Debug information screens
    /// - Interactive tools
    case viewController

    /// A developer option that displays a static value.
    ///
    /// Use this type for options that show read-only information, such as:
    /// - App version
    /// - Build number
    /// - Environment name
    /// - API endpoint URL
    case value
}

/// Represents a custom developer option that can be added to the Scyther menu.
///
/// `DeveloperOption` allows you to extend the Scyther debug menu with custom
/// functionality specific to your application. Options can either display static
/// information (value type) or navigate to a custom view controller.
///
/// ## Creating Value Options
///
/// Value options display static information in the menu:
///
/// ```swift
/// let versionOption = DeveloperOption(
///     name: "App Version",
///     value: "1.2.3 (456)",
///     icon: UIImage(systemName: "info.circle")
/// )
/// ```
///
/// ## Creating View Controller Options
///
/// View controller options navigate to a custom screen when tapped:
///
/// ```swift
/// let settingsOption = DeveloperOption(
///     name: "Advanced Settings",
///     icon: UIImage(systemName: "gear"),
///     viewController: AdvancedSettingsViewController()
/// )
/// ```
///
/// ## Adding to Scyther
///
/// Register your custom options with Scyther:
///
/// ```swift
/// Scyther.shared.developerOptions = [
///     versionOption,
///     settingsOption
/// ]
/// ```
///
/// - Note: This type is only available on iOS, tvOS, and watchOS platforms.
public struct DeveloperOption {
    /// Creates a value-based developer option that displays static information.
    ///
    /// Use this initializer for options that show read-only data in the menu,
    /// such as version numbers, environment details, or configuration values.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let buildOption = DeveloperOption(
    ///     name: "Build Number",
    ///     value: "12345",
    ///     icon: UIImage(systemName: "hammer")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - name: The display name for this option in the menu
    ///   - value: The value to display (e.g., version number, URL, identifier)
    ///   - icon: An optional icon to display alongside the option name
    public init(name: String, value: String, icon: UIImage? = nil) {
        self.type = .value
        self.name = name
        self.value = value
        self.icon = icon
    }

    /// Creates a view controller-based developer option that navigates to a custom screen.
    ///
    /// Use this initializer for options that require user interaction or display
    /// complex information that needs a dedicated view controller.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let debugOption = DeveloperOption(
    ///     name: "Debug Tools",
    ///     icon: UIImage(systemName: "wrench.and.screwdriver"),
    ///     viewController: DebugToolsViewController()
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - name: The display name for this option in the menu
    ///   - icon: An optional icon to display alongside the option name
    ///   - viewController: The view controller to present when this option is selected
    public init(name: String, icon: UIImage? = nil, viewController: UIViewController? = nil) {
        self.type = .viewController
        self.name = name
        self.icon = icon
        self.viewController = viewController
    }

    /// The type of developer option, determining its behavior and presentation.
    ///
    /// This property is set automatically based on which initializer is used
    /// and controls how the option is displayed in the menu.
    internal var type: DeveloperOptionType

    /// The display name for this developer option.
    ///
    /// This text appears in the Scyther menu and should clearly describe
    /// what the option represents or what action it performs.
    public var name: String

    /// The value to display for value-type options.
    ///
    /// This property is only used when `type` is `.value`. For view controller
    /// options, this will be `nil`.
    public var value: String?

    /// An optional icon to display alongside the option name.
    ///
    /// SF Symbols or custom images can be used to visually distinguish
    /// different options in the menu.
    public var icon: UIImage?

    /// The view controller to present for view controller-type options.
    ///
    /// This property is only used when `type` is `.viewController`. For value
    /// options, this will be `nil`.
    public var viewController: UIViewController?
}
#endif
