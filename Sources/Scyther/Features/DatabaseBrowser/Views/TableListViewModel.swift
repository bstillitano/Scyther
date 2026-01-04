//
//  TableListViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// View model for the table list view.
///
/// Manages the loading and display of tables for a specific database.
@MainActor
final class TableListViewModel: ViewModel {
    // MARK: - Properties

    /// The database being browsed.
    let database: DatabaseInfo

    // MARK: - Published Properties

    /// The list of tables in the database.
    @Published var tables: [TableInfo] = []

    /// Whether the tables are loading.
    @Published var isLoading: Bool = false

    /// Whether an error occurred.
    @Published var showingError: Bool = false

    /// The error message to display.
    @Published var errorMessage: String = ""

    /// The table selected to view its schema.
    @Published var selectedTableForSchema: TableInfo?

    // MARK: - Initialization

    init(database: DatabaseInfo) {
        self.database = database
        super.init()
    }

    // MARK: - Lifecycle

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadTables()
    }

    // MARK: - Actions

    /// Loads the list of tables from the database.
    func loadTables() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tables = try await database.adapter.tables()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Filters tables by search text.
    ///
    /// - Parameter searchText: The search text to filter by.
    /// - Returns: Filtered tables.
    func filteredTables(searchText: String) -> [TableInfo] {
        guard !searchText.isEmpty else { return tables }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
#endif
