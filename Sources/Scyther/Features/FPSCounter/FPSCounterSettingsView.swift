//
//  FPSCounterSettingsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import SwiftUI

/// A SwiftUI view for configuring the FPS counter overlay settings.
///
/// This view provides controls for:
/// - Toggling the FPS counter on/off
/// - Selecting the overlay position (corner of the screen)
///
/// All settings changes are immediately applied and persisted to UserDefaults.
struct FPSCounterSettingsView: View {
    @StateObject private var viewModel = FPSCounterSettingsViewModel()

    var body: some View {
        List {
            Section {
                Toggle(isOn: $viewModel.isEnabled) {
                    Label {
                        Text("Enable FPS Counter")
                    } icon: {
                        Image(systemName: "speedometer")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } footer: {
                Text("Displays a real-time frame rate indicator on screen.")
            }

            if viewModel.isEnabled {
                Section {
                    ForEach(FPSCounterPosition.allCases, id: \.rawValue) { position in
                        Button {
                            viewModel.selectPosition(position)
                        } label: {
                            HStack {
                                Text(position.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.selectedPosition == position {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Position")
                } footer: {
                    Text("Choose which corner of the screen to display the FPS counter.")
                }

                Section {
                    HStack {
                        Text("Current FPS")
                        Spacer()
                        Text("\(viewModel.currentFPS)")
                            .foregroundStyle(Color(FPSCounter.color(for: viewModel.currentFPS)))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Status")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("55+ FPS: Excellent", systemImage: "circle.fill")
                            .foregroundStyle(.green)
                        Label("30-54 FPS: Acceptable", systemImage: "circle.fill")
                            .foregroundStyle(.yellow)
                        Label("<30 FPS: Poor", systemImage: "circle.fill")
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle("FPS Counter")
        .animation(.default, value: viewModel.isEnabled)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onDisappear {
            viewModel.stopUpdatingFPS()
        }
    }
}

/// View model managing the FPS counter settings interface.
///
/// Handles loading settings from `FPSCounter` on first appearance and synchronizing
/// UI changes back to the singleton instance.
@MainActor
class FPSCounterSettingsViewModel: ViewModel {
    @Published var isEnabled: Bool = false {
        didSet {
            FPSCounter.instance.enabled = isEnabled
        }
    }

    @Published var selectedPosition: FPSCounterPosition = .topLeft
    @Published var currentFPS: Int = 0

    private var updateTimer: Timer?

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSettings()
        startUpdatingFPS()
    }

    @MainActor
    private func loadSettings() async {
        isEnabled = FPSCounter.instance.enabled
        selectedPosition = FPSCounter.instance.position
        currentFPS = FPSCounter.instance.currentFPS
    }

    @MainActor
    func selectPosition(_ position: FPSCounterPosition) {
        selectedPosition = position
        FPSCounter.instance.position = position
    }

    func startUpdatingFPS() {
        stopUpdatingFPS()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentFPS = FPSCounter.instance.currentFPS
            }
        }
    }

    func stopUpdatingFPS() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

#Preview {
    NavigationStack {
        FPSCounterSettingsView()
    }
}
#endif
