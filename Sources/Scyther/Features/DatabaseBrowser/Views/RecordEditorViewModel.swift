//
//  RecordEditorViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// The mode for the record editor.
enum RecordEditorMode {
    /// Adding a new record.
    case add

    /// Editing an existing record.
    case edit(DatabaseRecord)
}

/// View model for the record editor view.
///
/// Manages the creation and editing of database records.
@MainActor
final class RecordEditorViewModel: ViewModel {
    // MARK: - Properties

    /// The adapter for the database.
    let adapter: any DatabaseBrowserAdapter

    /// The table to add/edit records in.
    let table: TableInfo

    /// The table schema.
    let schema: TableSchema?

    /// The editor mode (add or edit).
    let mode: RecordEditorMode

    /// Callback when the record is saved.
    let onSave: () async -> Void

    // MARK: - Published Properties

    /// The current values for each column.
    @Published var values: [String: String] = [:]

    /// NULL state for each column.
    @Published var isNull: [String: Bool] = [:]

    /// Whether the save is in progress.
    @Published var isSaving: Bool = false

    /// Whether an error occurred.
    @Published var showingError: Bool = false

    /// The error message to display.
    @Published var errorMessage: String = ""

    /// Whether the save was successful (triggers dismiss).
    @Published var didSave: Bool = false

    // MARK: - Initialization

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
        super.init()
    }

    // MARK: - Lifecycle

    override func setup() {
        super.setup()
        initializeValues()
    }

    // MARK: - Computed Properties

    /// Whether this is adding a new record.
    var isAddMode: Bool {
        if case .add = mode { return true }
        return false
    }

    /// The title for the view.
    var title: String {
        isAddMode ? "Add Record" : "Edit Record"
    }

    /// The columns to display in the editor.
    var editableColumns: [ColumnInfo] {
        guard let schema = schema else { return [] }
        return schema.columns.filter { column in
            // Skip auto-increment primary keys in add mode
            if isAddMode && column.isPrimaryKey && column.type.uppercased().contains("INTEGER") {
                return false
            }
            return true
        }
    }

    // MARK: - Actions

    /// Saves the record.
    func save() async {
        isSaving = true
        defer { isSaving = false }

        // Build values dictionary
        var dbValues: [String: DatabaseValue] = [:]
        for column in editableColumns {
            if isNull[column.name] == true {
                dbValues[column.name] = .null
            } else if let stringValue = values[column.name] {
                dbValues[column.name] = parseValue(stringValue, forColumn: column)
            }
        }

        do {
            switch mode {
            case .add:
                _ = try await adapter.insert(into: table.name, values: dbValues)
            case .edit(let record):
                guard let primaryKey = record.primaryKey else {
                    throw DatabaseBrowserError.invalidPrimaryKey
                }
                try await adapter.update(in: table.name, primaryKey: primaryKey, values: dbValues)
            }

            await onSave()
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Toggles the NULL state for a column.
    func toggleNull(for column: String) {
        isNull[column] = !(isNull[column] ?? false)
        if isNull[column] == true {
            values[column] = ""
        }
    }

    // MARK: - Private Methods

    private func initializeValues() {
        guard let schema = schema else { return }

        switch mode {
        case .add:
            // Initialize with defaults or empty values
            for column in schema.columns {
                if let defaultValue = column.defaultValue {
                    values[column.name] = defaultValue
                } else {
                    values[column.name] = ""
                }
                isNull[column.name] = column.isNullable && column.defaultValue == nil
            }

        case .edit(let record):
            // Initialize with existing values
            for column in schema.columns {
                let value = record.values[column.name] ?? .null
                if value.isNull {
                    values[column.name] = ""
                    isNull[column.name] = true
                } else {
                    values[column.name] = value.displayString
                    isNull[column.name] = false
                }
            }
        }
    }

    private func parseValue(_ string: String, forColumn column: ColumnInfo) -> DatabaseValue {
        let type = column.type.uppercased()

        // Handle empty strings
        if string.isEmpty && column.isNullable {
            return .null
        }

        // Parse based on type
        if type.contains("INT") {
            if let intValue = Int64(string) {
                return .integer(intValue)
            }
        } else if type.contains("REAL") || type.contains("FLOAT") || type.contains("DOUBLE") {
            if let doubleValue = Double(string) {
                return .real(doubleValue)
            }
        } else if type.contains("BLOB") {
            // For blob, assume base64 encoded
            if let data = Data(base64Encoded: string) {
                return .blob(data)
            }
        }

        // Default to text
        return .text(string)
    }
}
#endif
