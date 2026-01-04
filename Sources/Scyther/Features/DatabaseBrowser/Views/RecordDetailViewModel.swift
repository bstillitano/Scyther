//
//  RecordDetailViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// View model for the record detail view.
///
/// Manages the display and editing of a single database record.
@MainActor
final class RecordDetailViewModel: ViewModel {
    // MARK: - Properties

    /// The adapter for the database.
    let adapter: any DatabaseBrowserAdapter

    /// The table the record belongs to.
    let table: TableInfo

    /// The table schema.
    let schema: TableSchema?

    /// Callback when the record is updated.
    let onUpdate: () async -> Void

    // MARK: - Published Properties

    /// The current record.
    @Published var record: DatabaseRecord

    /// Whether an error occurred.
    @Published var showingError: Bool = false

    /// The error message to display.
    @Published var errorMessage: String = ""

    /// Whether the delete confirmation is showing.
    @Published var showingDeleteConfirmation: Bool = false

    /// Whether the record was deleted (triggers navigation pop).
    @Published var wasDeleted: Bool = false

    // MARK: - Initialization

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
        super.init()
    }

    // MARK: - Computed Properties

    /// The sorted column names.
    var sortedColumns: [String] {
        record.sortedColumnNames
    }

    /// Gets column info for a column name.
    func columnInfo(for name: String) -> ColumnInfo? {
        schema?.columns.first { $0.name == name }
    }

    // MARK: - Actions

    /// Deletes the current record.
    func deleteRecord() async {
        guard let primaryKey = record.primaryKey else {
            errorMessage = "Cannot delete record without primary key"
            showingError = true
            return
        }

        do {
            try await adapter.delete(from: table.name, primaryKey: primaryKey)
            await onUpdate()
            wasDeleted = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Refreshes the record from the database.
    func refresh() async {
        guard let primaryKey = record.primaryKey else { return }

        do {
            if let updatedRecord = try await adapter.record(in: table.name, primaryKey: primaryKey) {
                record = updatedRecord
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
#endif
