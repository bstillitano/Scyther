//
//  SchemaViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// View model for the schema view.
///
/// Manages the loading and display of a table's schema.
@MainActor
final class SchemaViewModel: ViewModel {
    // MARK: - Properties

    /// The adapter for the database.
    let adapter: any DatabaseBrowserAdapter

    /// The table to show schema for.
    let table: TableInfo

    // MARK: - Published Properties

    /// The table schema.
    @Published var schema: TableSchema?

    /// Whether the schema is loading.
    @Published var isLoading: Bool = false

    /// Whether an error occurred.
    @Published var showingError: Bool = false

    /// The error message to display.
    @Published var errorMessage: String = ""

    // MARK: - Initialization

    init(adapter: any DatabaseBrowserAdapter, table: TableInfo) {
        self.adapter = adapter
        self.table = table
        super.init()
    }

    // MARK: - Lifecycle

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSchema()
    }

    // MARK: - Actions

    /// Loads the table schema.
    func loadSchema() async {
        isLoading = true
        defer { isLoading = false }

        do {
            schema = try await adapter.schema(for: table.name)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
#endif
