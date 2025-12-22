//
//  AppearanceOverridesViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import Foundation
import SwiftUI

/// View model managing the appearance override settings interface.
///
/// `AppearanceOverridesViewModel` coordinates between the UI layer and the ``AppearanceOverrides``
/// singleton, handling bidirectional data flow and state synchronization. It loads current settings
/// on first appearance and immediately applies any user changes back to the persistence layer.
///
/// ## Features
///
/// - **Color Scheme Selection**: Switch between System, Light, and Dark appearance modes
/// - **High Contrast Mode**: Toggle increased contrast for better visibility (iOS 17+)
/// - **Dynamic Type Override**: Test different text size categories from extra small to accessibility sizes
/// - **Automatic Persistence**: All changes are immediately saved to UserDefaults via ``AppearanceOverrides``
/// - **Reset Functionality**: Restore all settings to system defaults
///
/// ## Usage
///
/// The view model is designed to be used with ``AppearanceOverridesView`` and follows the MVVM pattern:
///
/// ```swift
/// struct AppearanceOverridesView: View {
///     @StateObject private var viewModel = AppearanceOverridesViewModel()
///
///     var body: some View {
///         List {
///             Toggle("Override Text Size", isOn: $viewModel.dynamicTypeOverrideEnabled)
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Lifecycle
/// - ``onFirstAppear()``
///
/// ### Color Scheme
/// - ``colorScheme``
/// - ``selectColorScheme(_:)``
///
/// ### High Contrast
/// - ``highContrastEnabled``
///
/// ### Dynamic Type
/// - ``dynamicTypeOverrideEnabled``
/// - ``selectedSizeCategory``
/// - ``sizeCategoryIndex``
///
/// ### Reset
/// - ``resetToDefaults()``
@MainActor
class AppearanceOverridesViewModel: ViewModel {
    /// The currently selected color scheme override.
    ///
    /// Use ``selectColorScheme(_:)`` to update this value and persist the change.
    @Published var colorScheme: ColorSchemeOverride = .system

    /// Whether high contrast mode is enabled.
    ///
    /// Setting this property automatically updates ``AppearanceOverrides/highContrastEnabled``
    /// and applies the change system-wide within the app.
    ///
    /// - Note: High contrast mode requires iOS 17 or later.
    @Published var highContrastEnabled: Bool = false {
        didSet {
            AppearanceOverrides.instance.highContrastEnabled = highContrastEnabled
        }
    }

    /// Whether Dynamic Type override is enabled.
    ///
    /// When `true`, the app uses ``selectedSizeCategory`` instead of the system text size.
    /// When `false`, the app respects the user's system Dynamic Type setting.
    @Published var dynamicTypeOverrideEnabled: Bool = false {
        didSet {
            if dynamicTypeOverrideEnabled {
                AppearanceOverrides.instance.contentSizeCategory = selectedSizeCategory
            } else {
                AppearanceOverrides.instance.contentSizeCategory = nil
            }
        }
    }

    /// The content size category to use when Dynamic Type override is enabled.
    ///
    /// Ranges from `.extraSmall` to `.accessibilityExtraExtraExtraLarge`. Use ``sizeCategoryIndex``
    /// for slider-based selection.
    @Published var selectedSizeCategory: UIContentSizeCategory = .large

    /// A computed index representing the position of ``selectedSizeCategory`` in the ordered list.
    ///
    /// This property provides a `Double` value suitable for binding to a `Slider` control,
    /// mapping the 12 content size categories to indices 0-11.
    ///
    /// Setting this value updates ``selectedSizeCategory`` and persists the change if
    /// ``dynamicTypeOverrideEnabled`` is `true`.
    var sizeCategoryIndex: Double {
        get { Double(selectedSizeCategory.orderedIndex) }
        set {
            let index = Int(newValue)
            guard index >= 0 && index < UIContentSizeCategory.allCategoriesOrdered.count else { return }
            selectedSizeCategory = UIContentSizeCategory.allCategoriesOrdered[index]
            if dynamicTypeOverrideEnabled {
                AppearanceOverrides.instance.contentSizeCategory = selectedSizeCategory
            }
        }
    }

    /// Loads current settings from ``AppearanceOverrides`` on first view appearance.
    ///
    /// This method populates all `@Published` properties with values from the singleton,
    /// ensuring the UI reflects the current persisted state.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSettings()
    }

    /// Loads settings from the ``AppearanceOverrides`` singleton.
    ///
    /// Called during ``onFirstAppear()`` to synchronize the view model state
    /// with the current persisted values.
    @MainActor
    private func loadSettings() async {
        colorScheme = AppearanceOverrides.instance.colorScheme
        highContrastEnabled = AppearanceOverrides.instance.highContrastEnabled

        if let category = AppearanceOverrides.instance.contentSizeCategory {
            dynamicTypeOverrideEnabled = true
            selectedSizeCategory = category
        } else {
            dynamicTypeOverrideEnabled = false
            selectedSizeCategory = .large
        }
    }

    /// Selects a new color scheme and persists the change.
    ///
    /// - Parameter scheme: The color scheme to apply (`.system`, `.light`, or `.dark`)
    func selectColorScheme(_ scheme: ColorSchemeOverride) {
        colorScheme = scheme
        AppearanceOverrides.instance.colorScheme = scheme
    }

    /// Resets all appearance overrides to system defaults.
    ///
    /// This method:
    /// - Sets color scheme to `.system`
    /// - Disables high contrast mode
    /// - Disables Dynamic Type override
    /// - Resets text size to `.large`
    /// - Calls ``AppearanceOverrides/resetToDefaults()`` to clear persisted values
    func resetToDefaults() {
        colorScheme = .system
        highContrastEnabled = false
        dynamicTypeOverrideEnabled = false
        selectedSizeCategory = .large
        AppearanceOverrides.instance.resetToDefaults()
    }
}
#endif
