//
//  DeepLinkTesterView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import SwiftUI

/// A SwiftUI view for testing deep links and URL schemes.
///
/// This view provides:
/// - A text field for entering custom URLs
/// - Developer-configured preset links
/// - History of previously tested links
/// - QR code scanner for scanning deep links
struct DeepLinkTesterView: View {
    @StateObject private var viewModel = DeepLinkTesterViewModel()
    @State private var showingScanner = false

    var body: some View {
        List {
            urlInputSection

            if !viewModel.presets.isEmpty {
                presetsSection
            }

            if !viewModel.history.isEmpty {
                historySection
            }
        }
        .navigationTitle("Deep Link Tester")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            QRCodeScannerView { scannedURL in
                viewModel.urlText = scannedURL
                showingScanner = false
            }
        }
        .alert("Result", isPresented: $viewModel.showingResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.resultMessage)
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    // MARK: - URL Input Section

    private var urlInputSection: some View {
        Section {
            TextField("Enter URL (e.g., myapp://home)", text: $viewModel.urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Button {
                Task {
                    await viewModel.openURL()
                }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    Text("Open URL")
                }
            }
            .disabled(viewModel.urlText.isEmpty || viewModel.isLoading)
        } header: {
            Text("Test URL")
        } footer: {
            Text("Enter a custom URL scheme (myapp://...) or universal link (https://...).")
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        Section {
            ForEach(viewModel.presets) { preset in
                Button {
                    Task {
                        await viewModel.openPreset(preset)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .foregroundStyle(.primary)
                            Text(preset.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("Configure presets via Scyther.deepLinks.presets")
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section {
            ForEach(viewModel.history) { entry in
                Button {
                    viewModel.urlText = entry.url
                } label: {
                    HStack {
                        Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(entry.success ? .green : .red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.url)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteHistoryEntry(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button(role: .destructive) {
                viewModel.clearHistory()
            } label: {
                Text("Clear History")
            }
        } header: {
            Text("History")
        }
    }
}

#Preview {
    NavigationStack {
        DeepLinkTesterView()
    }
}
#endif
