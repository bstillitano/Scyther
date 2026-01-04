//
//  QueryResult.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// Result of executing a SQL query.
///
/// This struct encapsulates the results of a SQL query execution,
/// including column names, row data, and execution metadata.
public struct QueryResult: Sendable {
    /// The column names in the result set.
    public let columns: [String]

    /// The rows returned by the query, each as a dictionary of column name to value.
    public let rows: [[String: DatabaseValue]]

    /// The number of rows affected (for INSERT, UPDATE, DELETE) or returned (for SELECT).
    public let rowsAffected: Int

    /// Whether this was a read-only query (SELECT, PRAGMA, EXPLAIN).
    public let isReadOnly: Bool

    /// The time taken to execute the query in seconds.
    public let executionTime: TimeInterval?

    /// Any error message from the query execution.
    public let errorMessage: String?

    /// Creates a successful query result.
    ///
    /// - Parameters:
    ///   - columns: The column names.
    ///   - rows: The result rows.
    ///   - rowsAffected: Number of rows affected/returned.
    ///   - isReadOnly: Whether this was a read-only query.
    ///   - executionTime: Time taken to execute.
    public init(
        columns: [String],
        rows: [[String: DatabaseValue]],
        rowsAffected: Int,
        isReadOnly: Bool,
        executionTime: TimeInterval? = nil
    ) {
        self.columns = columns
        self.rows = rows
        self.rowsAffected = rowsAffected
        self.isReadOnly = isReadOnly
        self.executionTime = executionTime
        self.errorMessage = nil
    }

    /// Creates an error result.
    ///
    /// - Parameter errorMessage: The error message.
    public init(errorMessage: String) {
        self.columns = []
        self.rows = []
        self.rowsAffected = 0
        self.isReadOnly = true
        self.executionTime = nil
        self.errorMessage = errorMessage
    }

    /// Whether the query was successful.
    public var isSuccess: Bool {
        errorMessage == nil
    }
}
#endif
