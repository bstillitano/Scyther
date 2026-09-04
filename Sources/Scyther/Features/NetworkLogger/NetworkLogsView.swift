//
//  NetworkLogsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import SwiftUI

/// A SwiftUI view that displays a list of captured network requests.
///
/// `NetworkLogsView` provides a searchable list interface for viewing all HTTP requests
/// captured by the network logger. Each request is displayed as a row showing the HTTP method,
/// status code, URL, and timing information.
///
/// ## Features
/// - Real-time updates as new requests are captured
/// - Search functionality across URLs, status codes, and HTTP methods
/// - Filter chips for method, status class, host, content type, API kind, GraphQL operation,
///   duration, exact status code, and recency, each opening a selection sheet, plus an all-filters
///   chip that edits every dimension from one Filters sheet
/// - Export of the requests currently shown as a zip archive (HAR plus raw bodies), with optional
///   redaction and a sensitivity alert before sharing
/// - Color-coded status indicators
/// - Navigation to detailed request view
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     NetworkLogsView()
/// }
/// ```
struct NetworkLogsView: View {
    /// Current search text for filtering network requests.
    @State private var searchText: String = ""

    /// The filter dimension whose sheet is currently presented, if any.
    @State private var editingDimension: NetworkLogFilterDimension?

    /// Whether the all-filters sheet is presented.
    @State private var showingAllFilters: Bool = false

    /// The requests snapshotted for export when the export button was tapped, if any.
    @State private var exportRequests: [HTTPRequest]?

    /// View model managing the network logs state and filtering.
    @StateObject private var viewModel: NetworkLogsViewModel = .init()

    var body: some View {
        List {
            ForEach(viewModel.requests) { request in
                NavigationLink {
                    LogDetailsView(httpRequest: request)
                } label: {
                    HTTPRequestView(request: request, searchTerm: searchText)
                }
                .listRowInsets(
                    .init(
                        top: .zero,
                        leading: .zero,
                        bottom: .zero,
                        trailing: 16
                    )
                )
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top, spacing: 0) {
            NetworkLogFilterBar(
                filter: viewModel.filter,
                chipTitle: viewModel.chipTitle(for:),
                onSelectAll: { showingAllFilters = true },
                onSelect: { editingDimension = $0 },
                onClear: { viewModel.clearFilter() }
            )
        }
        .sheet(isPresented: $showingAllFilters) {
            NetworkLogAllFiltersSheet(
                viewModel: NetworkLogAllFiltersSheetViewModel(
                    filter: viewModel.filter,
                    options: viewModel.options(for:),
                    onChange: { viewModel.filter = $0 }
                )
            )
        }
        .sheet(item: $editingDimension) { dimension in
            NetworkLogFilterSheet(
                viewModel: NetworkLogFilterSheetViewModel(
                    dimension: dimension,
                    options: viewModel.options(for: dimension),
                    selected: viewModel.filter.selection(for: dimension),
                    hostMode: viewModel.filter.hostMode,
                    onChange: { viewModel.filter.setSelection($0, for: dimension) },
                    onHostModeChange: { viewModel.filter.hostMode = $0 }
                )
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(localized("Export"), systemImage: "square.and.arrow.up") {
                    exportRequests = viewModel.requests
                }
                .disabled(viewModel.requests.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(localized("Delete"), systemImage: "trash", role: .destructive) {
                    Task {
                        await viewModel.didPressDeleteButton()
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { exportRequests.map(NetworkLogExportBatch.init) },
            set: { exportRequests = $0?.requests }
        )) { batch in
            NetworkLogExportSheet(viewModel: NetworkLogExportViewModel(requests: batch.requests))
        }
        .searchable(
            text: $searchText,
            prompt: localized("Search via URL, Operation, Status Code or Method")
        )
        .navigationTitle(localized("Network Logs"))
        .onChange(of: searchText) {
            viewModel.setSearchTerm(to: $0)
        }
    }
}

/// An identifiable wrapper for the requests snapshotted at export time, used to drive the export sheet.
struct NetworkLogExportBatch: Identifiable {
    let id = UUID()
    let requests: [HTTPRequest]
}
