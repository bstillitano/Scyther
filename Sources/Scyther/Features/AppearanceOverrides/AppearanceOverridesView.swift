//
//  AppearanceOverridesView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import SwiftUI

/// A SwiftUI view for configuring appearance override settings.
///
/// This view provides controls for:
/// - Selecting a color scheme (System, Light, Dark)
/// - Toggling high contrast mode (iOS 17+)
/// - Selecting a Dynamic Type content size category
///
/// All settings changes are immediately applied and persisted to UserDefaults.
struct AppearanceOverridesView: View {
    @StateObject private var viewModel = AppearanceOverridesViewModel()

    var body: some View {
        List {
            dynamicTypeSection

            colorSchemeSection

            if #available(iOS 17.0, *) {
                highContrastSection
            }

            resetSection
        }
        .navigationTitle("Appearance")
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    // MARK: - Sections

    private var colorSchemeSection: some View {
        Section {
            ForEach(ColorSchemeOverride.allCases, id: \.rawValue) { scheme in
                Button {
                    viewModel.selectColorScheme(scheme)
                } label: {
                    HStack {
                        Label {
                            Text(scheme.displayName)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: iconName(for: scheme))
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        if viewModel.colorScheme == scheme {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        } header: {
            Text("Color Scheme")
        } footer: {
            Text("Override the system appearance for this app.")
        }
    }

    @available(iOS 17.0, *)
    private var highContrastSection: some View {
        Section {
            Toggle(isOn: $viewModel.highContrastEnabled) {
                Label {
                    Text("Increase Contrast")
                } icon: {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Text("Accessibility")
        } footer: {
            Text("Enables increased contrast colors for better visibility.")
        }
    }

    private var dynamicTypeSection: some View {
        Section {
            Toggle(isOn: $viewModel.dynamicTypeOverrideEnabled) {
                Label {
                    Text("Override Text Size")
                } icon: {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(Color.accentColor)
                }
            }

            if viewModel.dynamicTypeOverrideEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Size:")
                        Spacer()
                        Text(viewModel.selectedSizeCategory.displayName)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $viewModel.sizeCategoryIndex,
                        in: 0...11,
                        step: 1
                    )

                    HStack {
                        Text("Aa")
                            .font(.caption2)
                        Spacer()
                        Text("Aa")
                            .font(.largeTitle)
                    }
                    .foregroundStyle(.secondary)
                }

                if viewModel.selectedSizeCategory.isAccessibilityCategory {
                    Label {
                        Text("Accessibility sizes may cause layout issues in apps not designed for them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
        } header: {
            Text("Dynamic Type")
        } footer: {
            Text("Test how your app responds to different text size settings.")
        }
        .animation(.default, value: viewModel.dynamicTypeOverrideEnabled)
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.resetToDefaults()
            } label: {
                Text("Reset to System Defaults")
            }
        }
    }

    // MARK: - Helpers

    private func iconName(for scheme: ColorSchemeOverride) -> String {
        switch scheme {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceOverridesView()
    }
}
#endif
