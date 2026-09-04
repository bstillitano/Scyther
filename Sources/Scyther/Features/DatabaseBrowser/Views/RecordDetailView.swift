//
//  RecordDetailView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import SwiftUI

/// View for displaying and editing a single database record.
struct RecordDetailView: View {
    let adapter: any DatabaseBrowserAdapter
    let table: TableInfo
    let record: DatabaseRecord
    let schema: TableSchema?
    let onUpdate: () async -> Void

    @StateObject private var viewModel: RecordDetailViewModel
    @State private var showingEditSheet = false
    @Environment(\.dismiss) private var dismiss

    init(
        adapter: any DatabaseBrowserAdapter,
        table: TableInfo,
        record: DatabaseRecord,
        schema: TableSchema?,
        onUpdate: @escaping () async -> Void
    ) {
        self.adapter = adapter
        self.table = table
        self.record = record
        self.schema = schema
        self.onUpdate = onUpdate
        _viewModel = StateObject(wrappedValue: RecordDetailViewModel(
            adapter: adapter,
            table: table,
            record: record,
            schema: schema,
            onUpdate: onUpdate
        ))
    }

    var body: some View {
        List {
            // Primary Key Section
            if let pk = viewModel.record.primaryKey, !pk.isNull {
                Section {
                    LabeledContent(localized("Primary Key"), value: pk.displayString)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = pk.displayString
                            } label: {
                                Label(localized("Copy"), systemImage: "doc.on.doc")
                            }
                        }
                }
            }

            // All Columns
            Section {
                ForEach(viewModel.sortedColumns, id: \.self) { column in
                    columnRow(column)
                }
            } header: {
                Text(localized("Values"))
            }
        }
        .navigationTitle(localized("Record Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if adapter.supportsWrite {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    Button(role: .destructive) {
                        viewModel.showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                RecordEditorView(
                    adapter: adapter,
                    table: table,
                    schema: schema,
                    mode: .edit(viewModel.record),
                    onSave: {
                        await viewModel.refresh()
                        await onUpdate()
                    }
                )
            }
        }
        .alert(
            localized("Delete Record?"),
            isPresented: $viewModel.showingDeleteConfirmation
        ) {
            Button(localized("Delete"), role: .destructive) {
                Task { await viewModel.deleteRecord() }
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("This action cannot be undone."))
        }
        .alert(localized("Error"), isPresented: $viewModel.showingError) {
            Button(localized("OK"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.wasDeleted) { wasDeleted in
            if wasDeleted {
                dismiss()
            }
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func columnRow(_ column: String) -> some View {
        let value = viewModel.record.values[column] ?? .null
        let columnInfo = viewModel.columnInfo(for: column)
        let isPrimaryKey = columnInfo?.isPrimaryKey ?? false

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(column)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isPrimaryKey {
                    Text(verbatim: "PK")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.yellow.opacity(0.3))
                        .cornerRadius(3)
                }

                if let type = columnInfo?.type {
                    Text(type)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            valueDisplay(value)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                UIPasteboard.general.string = value.displayString
            } label: {
                Label(localized("Copy Value"), systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = column
            } label: {
                Label(localized("Copy Column Name"), systemImage: "textformat")
            }
        }
    }

    @ViewBuilder
    private func valueDisplay(_ value: DatabaseValue) -> some View {
        switch value {
        case .null:
            Text(verbatim: "NULL")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .italic()

        case .blob(let data):
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.blue)
                Text(verbatim: "\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .memory))")
                    .font(.body.monospaced())
            }

        case .text(let string):
            if string.count > 200 {
                NavigationLink {
                    TextReaderView(text: string, title: localized("Value"))
                } label: {
                    Text(string.prefix(100) + "...")
                        .font(.body.monospaced())
                        .lineLimit(3)
                }
            } else {
                Text(string)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

        case .integer(let int):
            Text(String(int))
                .font(.body.monospaced())
                .textSelection(.enabled)

        case .real(let double):
            Text(String(format: "%.6g", double))
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}
#endif
