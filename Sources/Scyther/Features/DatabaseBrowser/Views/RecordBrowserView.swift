//
//  RecordBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import SwiftUI

/// Paginated browser for table records with CRUD operations.
struct RecordBrowserView: View {
    let adapter: any DatabaseBrowserAdapter
    let table: TableInfo

    @StateObject private var viewModel: RecordBrowserViewModel
    @State private var showingAddRecord = false
    @State private var showingSchema = false

    init(adapter: any DatabaseBrowserAdapter, table: TableInfo) {
        self.adapter = adapter
        self.table = table
        _viewModel = StateObject(wrappedValue: RecordBrowserViewModel(adapter: adapter, table: table))
    }

    var body: some View {
        List {
            // Schema and Query links
            Section {
                Button {
                    showingSchema = true
                } label: {
                    Label("View Schema", systemImage: "tablecells")
                }
            }

            // Records
            Section {
                if viewModel.isLoading && viewModel.records.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if viewModel.records.isEmpty {
                    emptyStateView(
                        title: "No Records",
                        systemImage: "tray",
                        description: "This table is empty."
                    )
                } else {
                    ForEach(viewModel.records) { record in
                        NavigationLink {
                            RecordDetailView(
                                adapter: adapter,
                                table: table,
                                record: record,
                                schema: viewModel.schema,
                                onUpdate: { await viewModel.refresh() }
                            )
                        } label: {
                            recordRow(record)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if adapter.supportsWrite {
                                Button(role: .destructive) {
                                    viewModel.recordToDelete = record
                                    viewModel.showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    // Load more button
                    if viewModel.hasMore {
                        Button {
                            Task { await viewModel.loadMore() }
                        } label: {
                            HStack {
                                Spacer()
                                if viewModel.isLoading {
                                    ProgressView()
                                } else {
                                    Text("Load More...")
                                }
                                Spacer()
                            }
                        }
                        .disabled(viewModel.isLoading)
                    }
                }
            } header: {
                Text("Records (\(viewModel.totalCount))")
            }
        }
        .navigationTitle(table.name)
        .toolbar {
            if adapter.supportsWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddRecord = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingAddRecord) {
            NavigationStack {
                RecordEditorView(
                    adapter: adapter,
                    table: table,
                    schema: viewModel.schema,
                    mode: .add,
                    onSave: { await viewModel.refresh() }
                )
            }
        }
        .sheet(isPresented: $showingSchema) {
            NavigationStack {
                SchemaView(adapter: adapter, table: table)
            }
        }
        .alert(
            "Delete Record?",
            isPresented: $viewModel.showingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteRecord() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
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
    private func recordRow(_ record: DatabaseRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Primary key
            if let pk = record.primaryKey, !pk.isNull {
                Text("ID: \(pk.displayString)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Show first few columns
            let columns = Array(record.sortedColumnNames.prefix(3))
            ForEach(columns, id: \.self) { column in
                HStack(spacing: 4) {
                    Text(column)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(record.displayValue(for: column))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
            }

            if record.values.count > 3 {
                Text("+ \(record.values.count - 3) more columns")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
