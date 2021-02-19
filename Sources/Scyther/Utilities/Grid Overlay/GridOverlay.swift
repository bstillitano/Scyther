//
//  File.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

import UIKit

internal class GridOverlay {
    // MARK: - Static Data
    static let EnabledDefaultsKey: String = "scyther_grid_overlay_enabled"
    static let ColorDefaultsKey: String = "scyther_grid_overlay_color"
    static let OpacityDefaultsKey: String = "scyther_grid_overlay_opacity"
    static let SizeDefaultsKey: String = "scyther_grid_overlay_size"

    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `GridOverlay` class.
    static let instance = GridOverlay()
    

    /// Last known preference for whether or not the running application would like a grid overlay to be shown
    internal var enabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: GridOverlay.EnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: GridOverlay.EnabledDefaultsKey)
            InterfaceToolkit.instance.showGridOverlay()
        }
    }

    /// Color scheme of the grid that is overlayed
    internal var colorScheme: GridOverlayColorScheme {
        get {
            return GridOverlayColorScheme(rawValue: UserDefaults.standard.string(forKey: GridOverlay.ColorDefaultsKey) ?? "red") ?? .red
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: GridOverlay.ColorDefaultsKey)
            InterfaceToolkit.instance.gridOverlayView.colorScheme = newValue
        }
    }

    /// Opacity of the grid that is overlayed
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

    /// Individual gird size of the grid that is overlayed
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
