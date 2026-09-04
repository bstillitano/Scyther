//
//  AppearanceOverrides.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import UIKit

/// Defines the available color scheme override options.
///
/// Use this enum to force a specific appearance mode for the application,
/// overriding the system setting.
public enum ColorSchemeOverride: String, CaseIterable, Sendable {
    /// Follow the system's light/dark mode setting.
    case system
    /// Force light mode regardless of system setting.
    case light
    /// Force dark mode regardless of system setting.
    case dark

    /// The corresponding `UIUserInterfaceStyle` for this override.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Human-readable display name, resolved in Scyther's effective language on each access.
    var displayName: String {
        switch self {
        case .system: return localized("System")
        case .light: return localized("Light")
        case .dark: return localized("Dark")
        }
    }
}

/// A singleton manager for overriding appearance settings at runtime.
///
/// `AppearanceOverrides` allows developers and QA to test their app's appearance
/// under different conditions without changing device settings:
/// - **Color Scheme**: Force light mode, dark mode, or follow system
/// - **High Contrast**: Enable increased contrast mode (iOS 17+)
/// - **Dynamic Type**: Test all content size categories
///
/// Settings are persisted in `UserDefaults.scyther`, Scyther's private preferences suite,
/// and automatically restored on app launch.
///
/// ```swift
/// // Force dark mode
/// AppearanceOverrides.instance.colorScheme = .dark
///
/// // Enable high contrast
/// AppearanceOverrides.instance.highContrastEnabled = true
///
/// // Test with large accessibility text
/// AppearanceOverrides.instance.contentSizeCategory = .accessibilityExtraLarge
/// ```
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
///
/// ### Configuration
/// - ``colorScheme``
/// - ``highContrastEnabled``
/// - ``contentSizeCategory``
@MainActor
public final class AppearanceOverrides: Sendable {
    // MARK: - Static Data (nonisolated for cross-thread access)

    /// UserDefaults key for storing the color scheme override.
    nonisolated static let ColorSchemeDefaultsKey: String = "Scyther_appearance_color_scheme"

    /// UserDefaults key for storing the high contrast setting.
    nonisolated static let HighContrastDefaultsKey: String = "Scyther_appearance_high_contrast"

    /// UserDefaults key for storing the content size category.
    nonisolated static let ContentSizeCategoryDefaultsKey: String = "Scyther_appearance_content_size_category"

    /// Private Init to stop re-initialisation and allow singleton creation.
    private init() { }

    /// The shared singleton instance of `AppearanceOverrides`.
    ///
    /// Use this instance to access all appearance override functionality.
    public static let instance = AppearanceOverrides()

    // MARK: - Color Scheme

    /// The current color scheme override setting.
    ///
    /// Setting this value immediately applies the color scheme to all windows
    /// and persists the preference to `UserDefaults.scyther`.
    public nonisolated var colorScheme: ColorSchemeOverride {
        get {
            let rawValue = UserDefaults.scyther.string(forKey: AppearanceOverrides.ColorSchemeDefaultsKey) ?? "system"
            return ColorSchemeOverride(rawValue: rawValue) ?? .system
        }
        set {
            UserDefaults.scyther.setValue(newValue.rawValue, forKey: AppearanceOverrides.ColorSchemeDefaultsKey)
            Task { @MainActor in
                self.applyColorScheme()
            }
        }
    }

    // MARK: - High Contrast

    /// Whether high contrast mode is enabled.
    ///
    /// When enabled, the system uses increased contrast colors for better visibility.
    /// This setting requires iOS 17+ to take effect via trait overrides.
    /// The value is persisted to `UserDefaults.scyther`.
    public nonisolated var highContrastEnabled: Bool {
        get {
            return UserDefaults.scyther.bool(forKey: AppearanceOverrides.HighContrastDefaultsKey)
        }
        set {
            UserDefaults.scyther.setValue(newValue, forKey: AppearanceOverrides.HighContrastDefaultsKey)
            Task { @MainActor in
                self.applyTraitOverrides()
            }
        }
    }

    // MARK: - Content Size Category

    /// The current content size category override.
    ///
    /// Use this to test how your app responds to different Dynamic Type sizes.
    /// When set to `nil`, the system default is used.
    /// The value is persisted to `UserDefaults.scyther`.
    public nonisolated var contentSizeCategory: UIContentSizeCategory? {
        get {
            guard let rawValue = UserDefaults.scyther.string(forKey: AppearanceOverrides.ContentSizeCategoryDefaultsKey) else {
                return nil
            }
            return UIContentSizeCategory(rawValue: rawValue)
        }
        set {
            if let newValue = newValue {
                UserDefaults.scyther.setValue(newValue.rawValue, forKey: AppearanceOverrides.ContentSizeCategoryDefaultsKey)
            } else {
                UserDefaults.scyther.removeObject(forKey: AppearanceOverrides.ContentSizeCategoryDefaultsKey)
            }
            Task { @MainActor in
                self.applyTraitOverrides()
            }
        }
    }

    // MARK: - Application

    /// Applies all current appearance settings to all windows.
    ///
    /// Call this method when the app becomes active or when new windows are created
    /// to ensure overrides are applied consistently.
    public func applyAllOverrides() {
        applyColorScheme()
        applyTraitOverrides()
    }

    /// Applies the color scheme override to all windows.
    private func applyColorScheme() {
        let style = colorScheme.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    /// Applies trait overrides (high contrast, content size) to all window scenes.
    private func applyTraitOverrides() {
        if #available(iOS 17.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }

                // Apply high contrast override
                if highContrastEnabled {
                    windowScene.traitOverrides.accessibilityContrast = .high
                } else {
                    windowScene.traitOverrides.accessibilityContrast = .unspecified
                }

                // Apply content size category override
                if let category = contentSizeCategory {
                    windowScene.traitOverrides.preferredContentSizeCategory = category
                } else {
                    windowScene.traitOverrides.preferredContentSizeCategory = UIApplication.shared.preferredContentSizeCategory
                }
            }
        }
    }

    /// Resets all appearance overrides to system defaults.
    public func resetToDefaults() {
        UserDefaults.scyther.removeObject(forKey: AppearanceOverrides.ColorSchemeDefaultsKey)
        UserDefaults.scyther.removeObject(forKey: AppearanceOverrides.HighContrastDefaultsKey)
        UserDefaults.scyther.removeObject(forKey: AppearanceOverrides.ContentSizeCategoryDefaultsKey)
        applyAllOverrides()
    }

    // MARK: - Scene Observation

    /// Registers for scene connection notifications to apply overrides to new windows.
    internal func registerForSceneNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidActivate),
            name: UIScene.didActivateNotification,
            object: nil
        )
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        applyAllOverrides()
    }
}

// MARK: - Content Size Category Helpers

extension UIContentSizeCategory {
    /// All available content size categories in order from smallest to largest.
    public static let allCategoriesOrdered: [UIContentSizeCategory] = [
        .extraSmall,
        .small,
        .medium,
        .large,
        .extraLarge,
        .extraExtraLarge,
        .extraExtraExtraLarge,
        .accessibilityMedium,
        .accessibilityLarge,
        .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge
    ]

    /// Human-readable display name for this content size category.
    ///
    /// Resolved in Scyther's effective language on each access, so it follows a language
    /// override without a relaunch. Unknown categories fall back to their raw value.
    public var displayName: String {
        switch self {
        case .extraSmall: return localized("Extra Small")
        case .small: return localized("Small")
        case .medium: return localized("Medium")
        case .large: return localized("Large (Default)")
        case .extraLarge: return localized("Extra Large")
        case .extraExtraLarge: return localized("XX Large")
        case .extraExtraExtraLarge: return localized("XXX Large")
        case .accessibilityMedium: return localized("Accessibility M")
        case .accessibilityLarge: return localized("Accessibility L")
        case .accessibilityExtraLarge: return localized("Accessibility XL")
        case .accessibilityExtraExtraLarge: return localized("Accessibility XXL")
        case .accessibilityExtraExtraExtraLarge: return localized("Accessibility XXXL")
        default: return rawValue
        }
    }

    /// Short display name for use in compact UI.
    ///
    /// These are size abbreviations rather than words, so they are the same in every
    /// language and are deliberately not routed through `localized(_:)`.
    public var shortDisplayName: String {
        switch self {
        case .extraSmall: return "XS"
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .extraLarge: return "XL"
        case .extraExtraLarge: return "XXL"
        case .extraExtraExtraLarge: return "XXXL"
        case .accessibilityMedium: return "aM"
        case .accessibilityLarge: return "aL"
        case .accessibilityExtraLarge: return "aXL"
        case .accessibilityExtraExtraLarge: return "aXXL"
        case .accessibilityExtraExtraExtraLarge: return "aXXXL"
        default: return rawValue
        }
    }

    /// Whether this is an accessibility size category.
    public var isAccessibilityCategory: Bool {
        switch self {
        case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
             .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge:
            return true
        default:
            return false
        }
    }

    /// The index of this category in the ordered list (0-11).
    public var orderedIndex: Int {
        UIContentSizeCategory.allCategoriesOrdered.firstIndex(of: self) ?? 3
    }
}
#endif
