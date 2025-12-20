//
//  TouchVisualiserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A SwiftUI view for configuring touch visualization settings.
///
/// This view provides toggles to:
/// - Enable/disable touch visualization
/// - Show touch duration labels
/// - Show touch radius scaling
/// - Enable console logging of touches
///
/// The touch visualiser displays visual indicators on screen wherever touches occur,
/// which is useful for debugging touch interactions and creating demonstrations.
struct TouchVisualiserView: View {
    @StateObject private var viewModel = TouchVisualiserViewModel()

    var body: some View {
        List {
            Section {
                Toggle("Show screen touches", isOn: $viewModel.visualiseTouches)

                if viewModel.visualiseTouches {
                    Toggle("Show touch duration", isOn: $viewModel.showTouchDuration)
                    Toggle("Show touch radius", isOn: $viewModel.showTouchRadius)
                    Toggle("Log screen touches", isOn: $viewModel.loggingEnabled)
                }
            }
        }
        .navigationTitle("Visualise Touches")
        .animation(.default, value: viewModel.visualiseTouches)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

/// View model for the touch visualiser settings view.
///
/// Manages the state of touch visualization settings and synchronizes them
/// with the `InterfaceToolkit` configuration.
class TouchVisualiserViewModel: ViewModel {
    /// Whether touch visualization is enabled.
    @Published var visualiseTouches: Bool = false {
        didSet {
            InterfaceToolkit.instance.visualiseTouches = visualiseTouches
        }
    }

    /// Whether to show touch duration labels.
    @Published var showTouchDuration: Bool = false {
        didSet {
            InterfaceToolkit.instance.touchVisualiser.config.showsTouchDuration = showTouchDuration
        }
    }

    /// Whether to show touch radius scaling.
    @Published var showTouchRadius: Bool = false {
        didSet {
            InterfaceToolkit.instance.touchVisualiser.config.showsTouchRadius = showTouchRadius
        }
    }

    /// Whether to enable console logging of touches.
    @Published var loggingEnabled: Bool = false {
        didSet {
            InterfaceToolkit.instance.touchVisualiser.config.loggingEnabled = loggingEnabled
        }
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSettings()
    }

    /// Loads current settings from the InterfaceToolkit.
    @MainActor
    private func loadSettings() async {
        visualiseTouches = InterfaceToolkit.instance.visualiseTouches
        showTouchDuration = InterfaceToolkit.instance.touchVisualiser.config.showsTouchDuration
        showTouchRadius = InterfaceToolkit.instance.touchVisualiser.config.showsTouchRadius
        loggingEnabled = InterfaceToolkit.instance.touchVisualiser.config.loggingEnabled
    }
}

#Preview {
    NavigationStack {
        TouchVisualiserView()
    }
}
