//
//  GridOverlaySettingsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A SwiftUI view for configuring the grid overlay settings.
///
/// This view provides controls for:
/// - Toggling the grid overlay on/off
/// - Adjusting grid size and opacity with sliders
/// - Selecting from predefined color schemes
///
/// All settings changes are immediately applied and persisted to UserDefaults.
struct GridOverlaySettingsView: View {
    @StateObject private var viewModel = GridOverlayViewModel()

    var body: some View {
        List {
            Section {
                Toggle(localized("Enable Grid"), isOn: $viewModel.isEnabled)
            }

            if viewModel.isEnabled {
                Section(localized("Grid Options")) {
                    VStack(alignment: .leading) {
                        Text(localized("Grid Size: \(viewModel.gridSize)"))
                        Slider(
                            value: $viewModel.gridSizeFloat,
                            in: 1...100,
                            step: 1
                        )
                    }

                    VStack(alignment: .leading) {
                        Text(localized("Opacity: \(viewModel.opacity)%"))
                        Slider(
                            value: $viewModel.opacityFloat,
                            in: 1...100,
                            step: 1
                        )
                    }
                }

                Section(localized("Grid Color")) {
                    ForEach(GridOverlayColorScheme.allCases, id: \.rawValue) { color in
                        Button {
                            viewModel.selectColor(color)
                        } label: {
                            HStack {
                                Text(viewModel.displayName(for: color))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.selectedColor == color {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(localized("Grid Overlay"))
        .animation(.default, value: viewModel.isEnabled)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

#Preview {
    NavigationStack {
        GridOverlaySettingsView()
    }
}
