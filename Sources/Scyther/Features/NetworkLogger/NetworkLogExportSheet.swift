//
//  NetworkLogExportSheet.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI

/// A full-height sheet that builds the network log archive and shares it after a warning.
///
/// Opened from the export button on ``NetworkLogsView``. Shows a progress indicator while
/// ``NetworkLogExportViewModel`` writes the zip, then the archive name, request count, contents,
/// a redaction toggle that rebuilds the archive in place (the previous rows stay put with an
/// inline spinner in the File row), and a red Export button. Export shows the
/// sensitivity alert; confirming it opens the system share sheet. A close button sits in the
/// leading toolbar slot, matching the root menu. The archive is deleted when the sheet is dismissed.
struct NetworkLogExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: NetworkLogExportViewModel

    /// Whether the sensitivity alert is presented.
    @State private var showingWarning: Bool = false

    /// Whether the system share sheet is presented.
    @State private var showingShareSheet: Bool = false

    /// Creates the export sheet.
    ///
    /// - Parameter viewModel: The view model that builds and owns the archive.
    init(viewModel: NetworkLogExportViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                archiveSection
                contentsSection
                redactionSection
                exportSection
            }
            .navigationTitle("Export Network Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .alert("Export Sensitive Data?", isPresented: $showingWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Export", role: .destructive) {
                    showingShareSheet = true
                }
            } message: {
                Text(warningMessage)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = viewModel.archiveURL {
                    ActivityShareSheet(items: [url])
                        .presentationDetents([.medium, .large])
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    private var warningMessage: String {
        let base = "The archive contains the full headers, cookies, authentication tokens, and request and response bodies of the \(viewModel.requestCount) requests currently shown. This data may be extremely sensitive. Handle and share it with extreme care."
        return viewModel.redactSensitiveValues
            ? base + " Redaction is on, but it is best effort and not a guarantee of privacy."
            : base
    }

    @ViewBuilder
    private var archiveSection: some View {
        switch viewModel.state {
        case .preparing:
            Section("Archive") {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing archive of \(viewModel.requestCount) requests…")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        case .ready(let url):
            Section("Archive") {
                // The spinner stays mounted as a trailing accessory and only changes
                // opacity, so the row never re-lays out when a rebuild starts or ends.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("File")
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView()
                        .opacity(viewModel.isRebuilding ? 1 : 0)
                }
                LabeledContent("Requests", value: "\(viewModel.requestCount)")
            }
        case .failed(let message):
            Section("Archive") {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private var contentsSection: some View {
        Section("Contents") {
            Label("network-log.har (HAR 1.2)", systemImage: "doc.text")
            Label("Raw request and response bodies", systemImage: "folder")
            Label("cURL command per request", systemImage: "terminal")
        }
    }

    private var redactionSection: some View {
        Section {
            Toggle(
                "Redact sensitive values",
                isOn: Binding(
                    get: { viewModel.redactSensitiveValues },
                    set: { viewModel.setRedaction($0) }
                )
            )
        } header: {
            Text("Redaction")
        } footer: {
            Text("Replaces common tokens, cookies, passwords, and API keys in headers, URLs, bodies, and cURL commands with REDACTED. This is an attempt, not a guarantee of privacy.")
        }
    }

    private var exportSection: some View {
        Section {
            Button(role: .destructive) {
                showingWarning = true
            } label: {
                Text("Export")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .disabled(viewModel.archiveURL == nil || viewModel.isRebuilding)
            .listRowBackground(Color.clear)
            .listRowInsets(.init())
        }
    }
}
