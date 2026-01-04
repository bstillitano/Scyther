//
//  SQLQueryEditorViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// View model for the SQL query editor.
///
/// Manages the execution of raw SQL queries and display of results.
@MainActor
final class SQLQueryEditorViewModel: ViewModel {
    // MARK: - Properties

    /// The adapter for the database.
    let adapter: any DatabaseBrowserAdapter

    // MARK: - Published Properties

    /// Whether a query is executing.
    @Published var isExecuting: Bool = false

    /// The result of the last query.
    @Published var result: QueryResult?

    /// The error message from the last query.
    @Published var errorMessage: String?

    /// Query history.
    @Published var history: [String] = []

    // MARK: - Initialization

    init(adapter: any DatabaseBrowserAdapter) {
        self.adapter = adapter
        super.init()
    }

    // MARK: - Actions

    /// Executes a SQL query.
    ///
    /// - Parameter sql: The SQL query to execute.
    func execute(_ sql: String) async {
        let trimmedSQL = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSQL.isEmpty else { return }

        isExecuting = true
        result = nil
        errorMessage = nil

        defer { isExecuting = false }

        do {
            result = try await adapter.executeQuery(trimmedSQL)

            // Add to history if successful
            if !history.contains(trimmedSQL) {
                history.insert(trimmedSQL, at: 0)
                // Keep only last 20 queries
                if history.count > 20 {
                    history = Array(history.prefix(20))
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            result = nil
        }
    }

    /// Clears the current results.
    func clearResults() {
        result = nil
        errorMessage = nil
    }
}
#endif
