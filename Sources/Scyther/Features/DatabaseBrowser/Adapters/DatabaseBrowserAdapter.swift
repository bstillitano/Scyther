//
//  DatabaseBrowserAdapter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// A protocol for browsing and manipulating databases.
///
/// Conforming types provide access to database contents, allowing Scyther's
/// Database Browser to display tables, records, and execute queries.
///
/// ## Implementing a Custom Adapter
///
/// To support a third-party database (e.g., Realm, Firebase), implement this
/// protocol in your app and register the adapter with Scyther:
///
/// ```swift
/// class RealmDatabaseAdapter: DatabaseBrowserAdapter {
///     let identifier: String
///     let displayName: String
///     let databaseType: DatabaseType
///
///     init(realm: Realm) {
///         self.identifier = realm.configuration.fileURL?.path ?? UUID().uuidString
///         self.displayName = "Realm Database"
///         self.databaseType = .custom("Realm")
///     }
///
///     func tables() async throws -> [TableInfo] {
///         // Return Realm object schemas as TableInfo
///     }
///
///     // ... implement other required methods
/// }
///
/// // Register with Scyther
/// Scyther.database.registerAdapter(RealmDatabaseAdapter(realm: myRealm))
/// ```
///
/// ## Thread Safety
///
/// All methods are async and may be called from any actor. Implementations
/// should ensure thread-safe access to the underlying database.
public protocol DatabaseBrowserAdapter: AnyObject, Sendable {
    // MARK: - Identification

    /// A unique identifier for this database instance.
    ///
    /// This is typically the file path for file-based databases,
    /// or a UUID for in-memory or remote databases.
    var identifier: String { get }

    /// A human-readable name shown in the database list.
    var displayName: String { get }

    /// The type of database (SQLite, CoreData, custom, etc.).
    var databaseType: DatabaseType { get }

    /// The file path to the database, if applicable.
    ///
    /// Return `nil` for in-memory or remote databases.
    var filePath: String? { get }

    // MARK: - Capabilities

    /// Whether this adapter supports executing raw SQL queries.
    ///
    /// Return `true` for SQLite-based databases, `false` for others.
    var supportsRawSQL: Bool { get }

    /// Whether this adapter supports write operations (INSERT, UPDATE, DELETE).
    ///
    /// Return `false` for read-only databases or adapters.
    var supportsWrite: Bool { get }

    // MARK: - Schema Operations

    /// Returns all tables or collections in this database.
    ///
    /// - Returns: An array of table information.
    /// - Throws: `DatabaseBrowserError` if the operation fails.
    func tables() async throws -> [TableInfo]

    /// Returns detailed schema information for a specific table.
    ///
    /// - Parameter table: The name of the table.
    /// - Returns: The table schema including columns, foreign keys, and indexes.
    /// - Throws: `DatabaseBrowserError` if the table is not found or the operation fails.
    func schema(for table: String) async throws -> TableSchema

    // MARK: - Read Operations

    /// Returns records from a table with pagination support.
    ///
    /// - Parameters:
    ///   - table: The name of the table.
    ///   - offset: The number of records to skip (for pagination).
    ///   - limit: The maximum number of records to return.
    ///   - orderBy: Optional column name to sort by.
    ///   - ascending: Sort direction. `true` for ascending, `false` for descending.
    /// - Returns: An array of database records.
    /// - Throws: `DatabaseBrowserError` if the operation fails.
    func records(
        in table: String,
        offset: Int,
        limit: Int,
        orderBy: String?,
        ascending: Bool
    ) async throws -> [DatabaseRecord]

    /// Returns the total count of records in a table.
    ///
    /// - Parameter table: The name of the table.
    /// - Returns: The number of records.
    /// - Throws: `DatabaseBrowserError` if the operation fails.
    func recordCount(in table: String) async throws -> Int

    /// Returns a single record by its primary key.
    ///
    /// - Parameters:
    ///   - table: The name of the table.
    ///   - primaryKey: The primary key value.
    /// - Returns: The record if found, `nil` otherwise.
    /// - Throws: `DatabaseBrowserError` if the operation fails.
    func record(in table: String, primaryKey: DatabaseValue) async throws -> DatabaseRecord?

    // MARK: - Write Operations

    /// Inserts a new record into a table.
    ///
    /// - Parameters:
    ///   - table: The name of the table.
    ///   - values: The column values for the new record.
    /// - Returns: The inserted record with any auto-generated values (e.g., primary key).
    /// - Throws: `DatabaseBrowserError` if the operation fails or writes are not supported.
    func insert(into table: String, values: [String: DatabaseValue]) async throws -> DatabaseRecord

    /// Updates an existing record.
    ///
    /// - Parameters:
    ///   - table: The name of the table.
    ///   - primaryKey: The primary key of the record to update.
    ///   - values: The column values to update.
    /// - Throws: `DatabaseBrowserError` if the record is not found or the operation fails.
    func update(in table: String, primaryKey: DatabaseValue, values: [String: DatabaseValue]) async throws

    /// Deletes a record by its primary key.
    ///
    /// - Parameters:
    ///   - table: The name of the table.
    ///   - primaryKey: The primary key of the record to delete.
    /// - Throws: `DatabaseBrowserError` if the record is not found or the operation fails.
    func delete(from table: String, primaryKey: DatabaseValue) async throws

    // MARK: - Query Operations

    /// Executes a raw SQL query.
    ///
    /// Only available if `supportsRawSQL` is `true`.
    ///
    /// - Parameter sql: The SQL query to execute.
    /// - Returns: The query result including rows, columns, and metadata.
    /// - Throws: `DatabaseBrowserError` if the query is invalid or execution fails.
    func executeQuery(_ sql: String) async throws -> QueryResult
}

// MARK: - Default Implementations

public extension DatabaseBrowserAdapter {
    /// Default implementation returns `nil` for file path.
    var filePath: String? { nil }

    /// Default implementation throws `writeNotSupported`.
    func insert(into table: String, values: [String: DatabaseValue]) async throws -> DatabaseRecord {
        throw DatabaseBrowserError.writeNotSupported
    }

    /// Default implementation throws `writeNotSupported`.
    func update(in table: String, primaryKey: DatabaseValue, values: [String: DatabaseValue]) async throws {
        throw DatabaseBrowserError.writeNotSupported
    }

    /// Default implementation throws `writeNotSupported`.
    func delete(from table: String, primaryKey: DatabaseValue) async throws {
        throw DatabaseBrowserError.writeNotSupported
    }

    /// Default implementation throws `writeNotSupported`.
    func executeQuery(_ sql: String) async throws -> QueryResult {
        throw DatabaseBrowserError.writeNotSupported
    }
}
#endif
