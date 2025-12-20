//
//  GridOverlay.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if !os(macOS)
import UIKit

/// A singleton manager for displaying a customizable grid overlay on the application interface.
///
/// `GridOverlay` allows developers to show a visual grid over their app's UI to assist with
/// layout alignment and spacing verification. The grid's appearance can be customized with
/// different colors, opacity levels, and grid sizes.
///
/// Settings are persisted to `UserDefaults` and automatically applied when changed.
///
/// ```swift
/// // Enable the grid overlay
/// GridOverlay.instance.enabled = true
///
/// // Customize appearance
/// GridOverlay.instance.colorScheme = .blue
/// GridOverlay.instance.opacity = 0.5
/// GridOverlay.instance.size = 8
/// ```
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
///
/// ### Configuration
/// - ``enabled``
/// - ``colorScheme``
/// - ``opacity``
/// - ``size``
///
/// ### UserDefaults Keys
/// - ``EnabledDefaultsKey``
/// - ``ColorDefaultsKey``
/// - ``OpacityDefaultsKey``
/// - ``SizeDefaultsKey``
internal class GridOverlay {
    // MARK: - Static Data

    /// UserDefaults key for storing the grid overlay enabled state.
    static let EnabledDefaultsKey: String = "Scyther_grid_overlay_enabled"

    /// UserDefaults key for storing the grid overlay color scheme.
    static let ColorDefaultsKey: String = "Scyther_grid_overlay_color"

    /// UserDefaults key for storing the grid overlay opacity.
    static let OpacityDefaultsKey: String = "Scyther_grid_overlay_opacity"

    /// UserDefaults key for storing the grid overlay size.
    static let SizeDefaultsKey: String = "Scyther_grid_overlay_size"

    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// The shared singleton instance of `GridOverlay`.
    ///
    /// Use this instance to access all grid overlay functionality.
    static let instance = GridOverlay()


    /// Controls whether the grid overlay is visible on screen.
    ///
    /// Setting this to `true` displays the grid overlay over the entire application interface.
    /// The value is persisted to UserDefaults and restored on app launch.
    internal var enabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: GridOverlay.EnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: GridOverlay.EnabledDefaultsKey)
            Task { @MainActor in InterfaceToolkit.instance.showGridOverlay() }
        }
    }

    /// The color scheme used for the grid lines.
    ///
    /// Choose from predefined color schemes to ensure the grid is visible against
    /// your app's color scheme. The value is persisted to UserDefaults.
    internal var colorScheme: GridOverlayColorScheme {
        get {
            return GridOverlayColorScheme(rawValue: UserDefaults.standard.string(forKey: GridOverlay.ColorDefaultsKey) ?? "red") ?? .red
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: GridOverlay.ColorDefaultsKey)
            InterfaceToolkit.instance.gridOverlayView.colorScheme = newValue
        }
    }

    /// The opacity of the grid overlay.
    ///
    /// Valid range is 0.0 (fully transparent) to 1.0 (fully opaque).
    /// Adjust this to make the grid more or less prominent. The value is persisted to UserDefaults.
    internal var opacity: Float {
        get {
            guard let value: Float = UserDefaults.standard.object(forKey: GridOverlay.OpacityDefaultsKey) as? Float else {
                return Float(InterfaceToolkit.instance.gridOverlayView.opacity)
            }
            return value
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: GridOverlay.OpacityDefaultsKey)
            InterfaceToolkit.instance.gridOverlayView.opacity = CGFloat(newValue)
        }
    }

    /// The size of each grid square in points.
    ///
    /// Smaller values create a finer grid, larger values create a coarser grid.
    /// Common values range from 4 to 16 points. The value is persisted to UserDefaults.
    internal var size: Int {
        get {
            guard let value: Int = UserDefaults.standard.object(forKey: GridOverlay.SizeDefaultsKey) as? Int else {
                return InterfaceToolkit.instance.gridOverlayView.gridSize
            }
            return value
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: GridOverlay.SizeDefaultsKey)
            InterfaceToolkit.instance.gridOverlayView.gridSize = newValue
        }
    }
}
#endif
