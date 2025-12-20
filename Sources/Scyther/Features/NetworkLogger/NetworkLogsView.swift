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

    /// View model managing the network logs state and filtering.
    @StateObject private var viewModel: NetworkLogsViewModel = NetworkLogsViewModel()

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
                        trailing: 16)
                )
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search via URL, Status Code or Method"
        )
        .navigationTitle("Network logs")
        .onChange(of: searchText) {
            viewModel.setSearchTerm(to: $0)
        }
    }
}
