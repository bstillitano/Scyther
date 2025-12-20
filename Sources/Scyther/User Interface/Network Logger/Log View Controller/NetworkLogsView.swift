//
//  NetworkLogsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/6/2025.
//

import SwiftUI

struct NetworkLogsView: View {
    @State private var searchText: String = ""
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
