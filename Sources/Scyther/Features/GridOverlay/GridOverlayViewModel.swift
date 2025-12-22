//
//  GridOverlayViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model managing the grid overlay settings interface.
///
/// `GridOverlayViewModel` coordinates between the UI layer and the `GridOverlay` singleton,
/// handling bidirectional data flow for grid configuration settings. It loads initial settings
/// on first appearance and synchronizes user changes back to the persistent storage.
///
/// ## Features
///
/// - **Real-time Synchronization**: All UI changes are immediately propagated to `GridOverlay.instance`
/// - **Type Conversion**: Provides `Float` bindings for SwiftUI sliders while maintaining `Int` precision
/// - **Lazy Loading**: Settings are loaded on first appearance to avoid unnecessary work
/// - **Published Properties**: All UI-bound properties use `@Published` for automatic SwiftUI updates
///
/// ## Usage
///
/// ```swift
/// struct GridOverlaySettingsView: View {
///     @StateObject private var viewModel = GridOverlayViewModel()
///
///     var body: some View {
///         List {
///             Toggle("Enable grid", isOn: $viewModel.isEnabled)
///             Slider(value: $viewModel.gridSizeFloat, in: 1...100)
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
///
/// - ``onFirstAppear()``
///
/// ### Grid State
///
/// - ``isEnabled``
/// - ``gridSize``
/// - ``opacity``
/// - ``selectedColor``
///
/// ### Slider Bindings
///
/// - ``gridSizeFloat``
/// - ``opacityFloat``
///
/// ### Actions
///
/// - ``selectColor(_:)``
class GridOverlayViewModel: ViewModel {
    /// Whether the grid overlay is currently enabled.
    ///
    /// Changes to this property are immediately synchronized to `GridOverlay.instance.enabled`.
    @Published var isEnabled: Bool = false {
        didSet {
            GridOverlay.instance.enabled = isEnabled
        }
    }

    /// The spacing between grid lines in points.
    ///
    /// Valid range: 1-100. Changes are synchronized via ``gridSizeFloat``.
    @Published var gridSize: Int = 10

    /// The opacity of the grid overlay as a percentage (0-100).
    ///
    /// Internally stored as percentage for UI display. Converted to 0.0-1.0 range
    /// when synchronized via ``opacityFloat``.
    @Published var opacity: Int = 50

    /// The currently selected color scheme for the grid.
    ///
    /// Updated via ``selectColor(_:)`` which synchronizes to `GridOverlay.instance`.
    @Published var selectedColor: GridOverlayColorScheme = .red

    /// Float representation of ``gridSize`` for SwiftUI slider bindings.
    ///
    /// Setter automatically updates ``gridSize`` and synchronizes to `GridOverlay.instance.size`.
    var gridSizeFloat: Float {
        get { Float(gridSize) }
        set {
            gridSize = Int(newValue)
            GridOverlay.instance.size = gridSize
        }
    }

    /// Float representation of ``opacity`` for SwiftUI slider bindings.
    ///
    /// Setter converts percentage (0-100) to normalized value (0.0-1.0) and
    /// synchronizes to `GridOverlay.instance.opacity`.
    var opacityFloat: Float {
        get { Float(opacity) }
        set {
            opacity = Int(newValue)
            GridOverlay.instance.opacity = Float(opacity) / 100.0
        }
    }

    /// Loads initial settings from `GridOverlay.instance` on first view appearance.
    ///
    /// This method is called automatically when the view appears for the first time.
    /// It populates all published properties with current values from the singleton.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSettings()
    }

    /// Loads current settings from the `GridOverlay` singleton.
    ///
    /// Updates all published properties to reflect the current state of `GridOverlay.instance`:
    /// - Enabled state
    /// - Grid size
    /// - Opacity (converted from 0.0-1.0 to 0-100 percentage)
    /// - Selected color scheme
    @MainActor
    private func loadSettings() async {
        isEnabled = GridOverlay.instance.enabled
        gridSize = GridOverlay.instance.size
        opacity = Int(GridOverlay.instance.opacity * 100)
        selectedColor = GridOverlay.instance.colorScheme
    }

    /// Updates the selected color scheme and synchronizes to `GridOverlay.instance`.
    ///
    /// - Parameter color: The new color scheme to apply to the grid overlay.
    @MainActor
    func selectColor(_ color: GridOverlayColorScheme) {
        selectedColor = color
        GridOverlay.instance.colorScheme = color
    }
}
