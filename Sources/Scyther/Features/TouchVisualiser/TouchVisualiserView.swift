//
//  TouchVisualiserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

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

class TouchVisualiserViewModel: ViewModel {
    @Published var visualiseTouches: Bool = false {
        didSet {
            InterfaceToolkit.instance.visualiseTouches = visualiseTouches
        }
    }

    @Published var showTouchDuration: Bool = false {
        didSet {
            InterfaceToolkit.instance.touchVisualiser.config.showsTouchDuration = showTouchDuration
        }
    }

    @Published var showTouchRadius: Bool = false {
        didSet {
            InterfaceToolkit.instance.touchVisualiser.config.showsTouchRadius = showTouchRadius
        }
    }

    @Published var loggingEnabled: Bool = false {
        didSet {
            InterfaceToolkit.instance.touchVisualiser.config.loggingEnabled = loggingEnabled
        }
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSettings()
    }

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
