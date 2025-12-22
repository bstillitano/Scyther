//
//  TouchVisualiserViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model for the touch visualiser settings view.
///
/// `TouchVisualiserViewModel` manages the state of touch visualization settings and
/// synchronizes them with the `InterfaceToolkit` and `TouchVisualiser` configurations.
/// It provides reactive bindings for enabling/disabling touch visualization and
/// configuring visual feedback options.
///
/// ## Features
///
/// - **Touch Visualization Toggle**: Enable/disable on-screen touch indicators
/// - **Duration Display**: Show how long each touch has been active
/// - **Radius Scaling**: Visualize touch radius changes (force/pressure sensitivity)
/// - **Console Logging**: Log touch events to the Scyther console for debugging
/// - **Settings Persistence**: Automatically loads and saves settings through InterfaceToolkit
///
/// ## Usage
///
/// ```swift
/// let viewModel = TouchVisualiserViewModel()
/// await viewModel.onFirstAppear()
///
/// // Toggle touch visualization
/// viewModel.visualiseTouches = true
/// viewModel.showTouchDuration = true
/// viewModel.showTouchRadius = true
/// viewModel.loggingEnabled = true
/// ```
///
/// ## Topics
///
/// ### Creating a View Model
/// - ``init()``
///
/// ### Touch Visualization Settings
/// - ``visualiseTouches``
/// - ``showTouchDuration``
/// - ``showTouchRadius``
/// - ``loggingEnabled``
///
/// ### Lifecycle
/// - ``onFirstAppear()``
@MainActor
class TouchVisualiserViewModel: ViewModel {
    /// Whether touch visualization is enabled.
    ///
    /// When set to `true`, visual indicators appear on screen wherever touches occur.
    /// Changes to this property automatically update the `InterfaceToolkit` configuration.
    @Published var visualiseTouches: Bool = false {
        didSet {
            InterfaceToolkit.instance.visualiseTouches = visualiseTouches
        }
    }

    /// Whether to show touch duration labels.
    ///
    /// When enabled, displays how long each touch has been active in milliseconds.
    /// Changes to this property automatically update the `TouchVisualiser` configuration.
    @Published var showTouchDuration: Bool = false {
        didSet {
            TouchVisualiser.instance.config.showsTouchDuration = showTouchDuration
        }
    }

    /// Whether to show touch radius scaling.
    ///
    /// When enabled, visualizes changes in touch radius (useful for force/pressure-sensitive touches).
    /// Changes to this property automatically update the `TouchVisualiser` configuration.
    @Published var showTouchRadius: Bool = false {
        didSet {
            TouchVisualiser.instance.config.showsTouchRadius = showTouchRadius
        }
    }

    /// Whether to enable console logging of touches.
    ///
    /// When enabled, logs touch events (began, moved, ended) to the Scyther console for debugging.
    /// Changes to this property automatically update the `TouchVisualiser` configuration.
    @Published var loggingEnabled: Bool = false {
        didSet {
            TouchVisualiser.instance.config.loggingEnabled = loggingEnabled
        }
    }

    /// Prepares the view model when the view first appears.
    ///
    /// This method loads the current settings from the `TouchVisualiser` and `InterfaceToolkit`
    /// configurations to initialize the view model's published properties.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        loadSettings()
    }

    /// Loads current settings from the TouchVisualiser configuration.
    ///
    /// Synchronizes the view model's published properties with the current state
    /// of the touch visualization system.
    private func loadSettings() {
        visualiseTouches = InterfaceToolkit.instance.visualiseTouches
        showTouchDuration = TouchVisualiser.instance.config.showsTouchDuration
        showTouchRadius = TouchVisualiser.instance.config.showsTouchRadius
        loggingEnabled = TouchVisualiser.instance.config.loggingEnabled
    }
}
