//
//  DatabaseBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import SwiftUI

/// Main view for browsing all discovered databases.
///
/// This view displays a list of all available databases, organized into sections
/// for native SQLite databases and custom adapter databases.
struct DatabaseBrowserView: View {
    @StateObject private var viewModel = DatabaseBrowserViewModel()

    var body: some View {
        List {
            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            } else if viewModel.databases.isEmpty {
                Section {
                    emptyStateView(
                        title: "No Databases Found",
                        systemImage: "cylinder.fill",
                        description: "No SQLite databases were found in this app's container. If using a custom database, register an adapter with Scyther.database.registerAdapter()."
                    )
                }
            } else {
                // Native SQLite databases
                if !viewModel.nativeDatabases.isEmpty {
                    Section {
                        ForEach(viewModel.nativeDatabases) { database in
                            NavigationLink {
                                TableListView(database: database)
                            } label: {
                                databaseRow(database)
                            }
                        }
                    } header: {
                        Text("SQLite Databases")
                    }
                }

                // Custom adapter databases
                if !viewModel.customDatabases.isEmpty {
                    Section {
                        ForEach(viewModel.customDatabases) { database in
                            NavigationLink {
                                TableListView(database: database)
                            } label: {
                                databaseRow(database)
                            }
                        }
                    } header: {
                        Text("Custom Databases")
                    }
                }
            }
        }
        .navigationTitle("Database Browser")
        .refreshable {
            await viewModel.refresh()
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
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
    private func databaseRow(_ database: DatabaseInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: database.type.iconName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(database.name)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(database.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let size = database.formattedFileSize {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        DatabaseBrowserView()
    }
}
#endif
