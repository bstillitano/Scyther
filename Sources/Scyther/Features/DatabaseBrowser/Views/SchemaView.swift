//
//  SchemaView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import SwiftUI

/// Shows the schema of a database table.
///
/// Displays columns, types, constraints, foreign keys, and indexes.
struct SchemaView: View {
    let adapter: any DatabaseBrowserAdapter
    let table: TableInfo
    @StateObject private var viewModel: SchemaViewModel
    @Environment(\.dismiss) private var dismiss

    init(adapter: any DatabaseBrowserAdapter, table: TableInfo) {
        self.adapter = adapter
        self.table = table
        _viewModel = StateObject(wrappedValue: SchemaViewModel(adapter: adapter, table: table))
    }

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
            } else if let schema = viewModel.schema {
                // Columns
                Section {
                    ForEach(schema.columns) { column in
                        columnRow(column)
                    }
                } header: {
                    Text("Columns (\(schema.columns.count))")
                }

                // Foreign Keys
                if !schema.foreignKeys.isEmpty {
                    Section {
                        ForEach(schema.foreignKeys) { fk in
                            foreignKeyRow(fk)
                        }
                    } header: {
                        Text("Foreign Keys")
                    }
                }

                // Indexes
                if !schema.indexes.isEmpty {
                    Section {
                        ForEach(schema.indexes) { index in
                            indexRow(index)
                        }
                    } header: {
                        Text("Indexes")
                    }
                }
            }
        }
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
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

    // MARK: - Row Views

    @ViewBuilder
    private func columnRow(_ column: ColumnInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(column.name)
                    .font(.body.monospaced())

                Spacer()

                if column.isPrimaryKey {
                    Text("PK")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.3))
                        .cornerRadius(4)
                }
            }

            HStack(spacing: 8) {
                Text(column.type)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if !column.isNullable {
                    Text("NOT NULL")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let defaultValue = column.defaultValue {
                    Text("DEFAULT: \(defaultValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func foreignKeyRow(_ fk: ForeignKeyInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fk.column)
                .font(.body.monospaced())

            Text("→ \(fk.referencedTable).\(fk.referencedColumn)")
                .font(.caption.monospaced())
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func indexRow(_ index: IndexInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(index.name)
                    .font(.body.monospaced())

                Spacer()

                if index.isUnique {
                    Text("UNIQUE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.3))
                        .cornerRadius(4)
                }
            }

            if !index.columns.isEmpty {
                Text(index.columns.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
