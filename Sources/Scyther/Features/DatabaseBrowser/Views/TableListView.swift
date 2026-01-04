//
//  TableListView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import SwiftUI

/// Shows all tables in a database with navigation to records and schema.
struct TableListView: View {
    let database: DatabaseInfo
    @StateObject private var viewModel: TableListViewModel
    @State private var searchText = ""

    init(database: DatabaseInfo) {
        self.database = database
        _viewModel = StateObject(wrappedValue: TableListViewModel(database: database))
    }

    private var filteredTables: [TableInfo] {
        viewModel.filteredTables(searchText: searchText)
    }

    var body: some View {
        List {
            // SQL Query Editor (if supported)
            if database.adapter.supportsRawSQL {
                Section {
                    NavigationLink {
                        SQLQueryEditorView(adapter: database.adapter)
                    } label: {
                        Label("SQL Query Editor", systemImage: "terminal")
                    }
                }
            }

            // Tables
            Section {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if filteredTables.isEmpty {
                    if searchText.isEmpty {
                        emptyStateView(
                            title: "No Tables",
                            systemImage: "tablecells",
                            description: "This database contains no tables."
                        )
                    } else {
                        emptyStateView(
                            title: "No Results",
                            systemImage: "magnifyingglass",
                            description: "No tables matching '\(searchText)'"
                        )
                    }
                } else {
                    ForEach(filteredTables) { table in
                        NavigationLink {
                            RecordBrowserView(adapter: database.adapter, table: table)
                        } label: {
                            tableRow(table)
                        }
                        .contextMenu {
                            Button {
                                viewModel.selectedTableForSchema = table
                            } label: {
                                Label("View Schema", systemImage: "tablecells")
                            }
                        }
                    }
                }
            } header: {
                Text("Tables (\(viewModel.tables.count))")
            }
        }
        .navigationTitle(database.name)
        .searchable(text: $searchText, prompt: "Search tables")
        .refreshable {
            await viewModel.loadTables()
        }
        .sheet(item: $viewModel.selectedTableForSchema) { table in
            NavigationStack {
                SchemaView(adapter: database.adapter, table: table)
            }
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func emptyStateView(title: String, systemImage: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Row Views

    @ViewBuilder
    private func tableRow(_ table: TableInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: table.isView ? "eye.fill" : "tablecells.fill")
                .foregroundStyle(table.isView ? .orange : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .lineLimit(1)

                Text(table.isView ? "View" : "Table")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
