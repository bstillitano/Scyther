//
//  RecordEditorView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import SwiftUI

/// Form for adding or editing database records.
struct RecordEditorView: View {
    let adapter: any DatabaseBrowserAdapter
    let table: TableInfo
    let schema: TableSchema?
    let mode: RecordEditorMode
    let onSave: () async -> Void

    @StateObject private var viewModel: RecordEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        adapter: any DatabaseBrowserAdapter,
        table: TableInfo,
        schema: TableSchema?,
        mode: RecordEditorMode,
        onSave: @escaping () async -> Void
    ) {
        self.adapter = adapter
        self.table = table
        self.schema = schema
        self.mode = mode
        self.onSave = onSave
        _viewModel = StateObject(wrappedValue: RecordEditorViewModel(
            adapter: adapter,
            table: table,
            schema: schema,
            mode: mode,
            onSave: onSave
        ))
    }

    var body: some View {
        Form {
            if viewModel.editableColumns.isEmpty {
                Section {
                    emptyStateView(
                        title: "No Schema",
                        systemImage: "exclamationmark.triangle",
                        description: "Could not load table schema. Cannot edit records."
                    )
                }
            } else {
                ForEach(viewModel.editableColumns) { column in
                    columnEditor(column)
                }
            }
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.didSave) { didSave in
            if didSave {
                dismiss()
            }
        }
        .interactiveDismissDisabled(viewModel.isSaving)
    }

    // MARK: - Column Editors

    @ViewBuilder
    private func columnEditor(_ column: ColumnInfo) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // Column header
                HStack {
                    Text(column.name)
                        .font(.headline)

                    if column.isPrimaryKey {
                        Text("PK")
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.3))
                            .cornerRadius(3)
                    }

                    Spacer()

                    Text(column.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // NULL toggle
                if column.isNullable {
                    Toggle("NULL", isOn: Binding(
                        get: { viewModel.isNull[column.name] ?? false },
                        set: { _ in viewModel.toggleNull(for: column.name) }
                    ))
                    .font(.caption)
                }

                // Value input
                if !(viewModel.isNull[column.name] ?? false) {
                    valueInput(for: column)
                }
            }
        }
    }

    @ViewBuilder
    private func valueInput(for column: ColumnInfo) -> some View {
        let type = column.type.uppercased()
        let binding = Binding(
            get: { viewModel.values[column.name] ?? "" },
            set: { viewModel.values[column.name] = $0 }
        )

        if type.contains("TEXT") || type.contains("VARCHAR") || type.contains("CHAR") {
            // Multi-line text input for TEXT types
            TextField("Value", text: binding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        } else if type.contains("INT") {
            // Number input for integers
            TextField("Value", text: binding)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
        } else if type.contains("REAL") || type.contains("FLOAT") || type.contains("DOUBLE") {
            // Decimal input for floats
            TextField("Value", text: binding)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
        } else if type.contains("BLOB") {
            // Base64 input for blobs
            VStack(alignment: .leading, spacing: 4) {
                TextField("Base64 Data", text: binding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.body.monospaced())
                Text("Enter data as Base64-encoded string")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            // Default text input
            TextField("Value", text: binding)
                .textFieldStyle(.roundedBorder)
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
}
#endif
