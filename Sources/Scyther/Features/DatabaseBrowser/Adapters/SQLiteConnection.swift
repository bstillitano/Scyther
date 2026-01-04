//
//  SQLiteConnection.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation
import SQLite3

/// A thread-safe wrapper around the SQLite C API.
///
/// This class provides low-level database operations using the sqlite3 C library
/// available on iOS without additional dependencies.
///
/// ## Thread Safety
///
/// All database operations are serialized on a dedicated dispatch queue to ensure
/// thread-safe access to the underlying SQLite connection.
///
/// ## Usage
///
/// ```swift
/// let connection = try SQLiteConnection(path: "/path/to/database.sqlite")
/// let results = try connection.query("SELECT * FROM users")
/// try connection.execute("INSERT INTO users (name) VALUES (?)", parameters: ["Alice"])
/// ```
final class SQLiteConnection: @unchecked Sendable {
    /// The underlying SQLite database handle.
    private var db: OpaquePointer?

    /// The path to the database file.
    let path: String

    /// A serial queue for thread-safe database access.
    private let queue = DispatchQueue(label: "com.scyther.sqlite", qos: .userInitiated)

    /// Opens a connection to a SQLite database.
    ///
    /// - Parameter path: The file path to the database.
    /// - Throws: `DatabaseBrowserError.connectionFailed` if the connection fails.
    init(path: String) throws {
        self.path = path

        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        let result = sqlite3_open_v2(path, &connection, flags, nil)
        guard result == SQLITE_OK, let connection = connection else {
            let errorMessage = connection.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(connection)
            throw DatabaseBrowserError.connectionFailed(errorMessage)
        }

        self.db = connection

        // Enable foreign keys
        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Query Execution

    /// Executes a query and returns results.
    ///
    /// - Parameters:
    ///   - sql: The SQL query to execute.
    ///   - parameters: Optional parameters for prepared statement binding.
    /// - Returns: An array of rows, each as a dictionary of column name to value.
    /// - Throws: `DatabaseBrowserError.queryFailed` if execution fails.
    func query(_ sql: String, parameters: [Any] = []) throws -> [[String: DatabaseValue]] {
        try queue.sync {
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                throw DatabaseBrowserError.queryFailed(error)
            }

            defer { sqlite3_finalize(statement) }

            // Bind parameters
            for (index, param) in parameters.enumerated() {
                try bind(param, to: statement, at: Int32(index + 1))
            }

            var results: [[String: DatabaseValue]] = []
            let columnCount = sqlite3_column_count(statement)

            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: DatabaseValue] = [:]
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(statement, i))
                    row[name] = value(from: statement, column: i)
                }
                results.append(row)
            }

            return results
        }
    }

    /// Executes a statement that doesn't return results (INSERT, UPDATE, DELETE).
    ///
    /// - Parameters:
    ///   - sql: The SQL statement to execute.
    ///   - parameters: Optional parameters for prepared statement binding.
    /// - Throws: `DatabaseBrowserError.queryFailed` if execution fails.
    func execute(_ sql: String, parameters: [Any] = []) throws {
        try queue.sync {
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                throw DatabaseBrowserError.queryFailed(error)
            }

            defer { sqlite3_finalize(statement) }

            for (index, param) in parameters.enumerated() {
                try bind(param, to: statement, at: Int32(index + 1))
            }

            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
                let error = String(cString: sqlite3_errmsg(db))
                throw DatabaseBrowserError.queryFailed(error)
            }
        }
    }

    /// Executes a query and returns the result with timing.
    ///
    /// - Parameter sql: The SQL query to execute.
    /// - Returns: A `QueryResult` with rows, columns, and execution time.
    /// - Throws: `DatabaseBrowserError` if execution fails.
    func executeWithResult(_ sql: String) throws -> QueryResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isSelect = trimmed.hasPrefix("SELECT") ||
                       trimmed.hasPrefix("PRAGMA") ||
                       trimmed.hasPrefix("EXPLAIN")

        if isSelect {
            let rows = try query(sql)
            let columns = rows.first?.keys.sorted() ?? []
            let executionTime = CFAbsoluteTimeGetCurrent() - startTime

            return QueryResult(
                columns: columns,
                rows: rows,
                rowsAffected: rows.count,
                isReadOnly: true,
                executionTime: executionTime
            )
        } else {
            try execute(sql)
            let executionTime = CFAbsoluteTimeGetCurrent() - startTime
            let changes = queue.sync { Int(sqlite3_changes(db)) }

            return QueryResult(
                columns: [],
                rows: [],
                rowsAffected: changes,
                isReadOnly: false,
                executionTime: executionTime
            )
        }
    }

    /// Returns the last inserted row ID.
    var lastInsertRowID: Int64 {
        queue.sync { sqlite3_last_insert_rowid(db) }
    }

    /// Returns the number of rows changed by the last statement.
    var changesCount: Int {
        queue.sync { Int(sqlite3_changes(db)) }
    }

    // MARK: - Private Helpers

    /// Binds a value to a prepared statement.
    private func bind(_ value: Any, to statement: OpaquePointer?, at index: Int32) throws {
        var result: Int32 = SQLITE_OK

        switch value {
        case let intValue as Int:
            result = sqlite3_bind_int64(statement, index, Int64(intValue))
        case let int64Value as Int64:
            result = sqlite3_bind_int64(statement, index, int64Value)
        case let int32Value as Int32:
            result = sqlite3_bind_int64(statement, index, Int64(int32Value))
        case let doubleValue as Double:
            result = sqlite3_bind_double(statement, index, doubleValue)
        case let floatValue as Float:
            result = sqlite3_bind_double(statement, index, Double(floatValue))
        case let stringValue as String:
            result = sqlite3_bind_text(statement, index, (stringValue as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case let dataValue as Data:
            result = dataValue.withUnsafeBytes { pointer in
                sqlite3_bind_blob(statement, index, pointer.baseAddress, Int32(dataValue.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        case is NSNull:
            result = sqlite3_bind_null(statement, index)
        case let dbValue as DatabaseValue:
            try bind(dbValue.anyValue, to: statement, at: index)
            return
        case let boolValue as Bool:
            result = sqlite3_bind_int64(statement, index, boolValue ? 1 : 0)
        default:
            let stringValue = String(describing: value)
            result = sqlite3_bind_text(statement, index, (stringValue as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        guard result == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw DatabaseBrowserError.queryFailed("Failed to bind parameter: \(error)")
        }
    }

    /// Extracts a value from a result row.
    private func value(from statement: OpaquePointer?, column: Int32) -> DatabaseValue {
        let type = sqlite3_column_type(statement, column)

        switch type {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            if let text = sqlite3_column_text(statement, column) {
                return .text(String(cString: text))
            }
            return .text("")
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(statement, column) {
                let count = Int(sqlite3_column_bytes(statement, column))
                return .blob(Data(bytes: bytes, count: count))
            }
            return .blob(Data())
        case SQLITE_NULL:
            return .null
        default:
            return .null
        }
    }
}
#endif
