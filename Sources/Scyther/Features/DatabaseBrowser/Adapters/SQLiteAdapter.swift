//
//  SQLiteAdapter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// Native SQLite adapter supporting CoreData and SwiftData databases.
///
/// This adapter uses the sqlite3 C API to provide full database browsing
/// and CRUD operations for any SQLite database file.
///
/// ## Supported Database Types
///
/// - **SQLite**: Standard SQLite databases
/// - **CoreData**: Automatically detected by Z-prefixed tables
/// - **SwiftData**: Automatically detected by SWIFT-prefixed tables
final class SQLiteAdapter: DatabaseBrowserAdapter, @unchecked Sendable {
    // MARK: - Properties

    public let identifier: String
    public let displayName: String
    public let databaseType: DatabaseType
    public let filePath: String?
    public let supportsRawSQL: Bool = true
    public let supportsWrite: Bool = true

    /// The underlying SQLite connection.
    private let connection: SQLiteConnection

    // MARK: - Initialization

    /// Creates a new SQLite adapter for a database file.
    ///
    /// - Parameters:
    ///   - path: The file path to the SQLite database.
    ///   - name: Optional display name. Defaults to the filename.
    ///   - type: The database type. Defaults to auto-detection.
    /// - Throws: `DatabaseBrowserError.connectionFailed` if the connection fails.
    init(path: String, name: String? = nil, type: DatabaseType? = nil) throws {
        self.filePath = path
        self.identifier = path
        self.displayName = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.connection = try SQLiteConnection(path: path)

        // Auto-detect database type if not specified
        if let type = type {
            self.databaseType = type
        } else {
            self.databaseType = try Self.detectDatabaseType(connection: connection)
        }
    }

    // MARK: - Schema Operations

    public func tables() async throws -> [TableInfo] {
        let sql = """
            SELECT name, type FROM sqlite_master
            WHERE type IN ('table', 'view')
            AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """

        let results = try connection.query(sql)

        return results.compactMap { row in
            guard case .text(let name) = row["name"] else { return nil }
            let isView = row["type"]?.textValue == "view"
            return TableInfo(name: name, isView: isView)
        }
    }

    public func schema(for table: String) async throws -> TableSchema {
        // Get column information
        let columnResults = try connection.query("PRAGMA table_info('\(escapeSQLIdentifier(table))')")

        let columns = columnResults.compactMap { row -> ColumnInfo? in
            guard case .text(let name) = row["name"],
                  case .text(let type) = row["type"] else { return nil }

            let isPrimaryKey = (row["pk"]?.integerValue ?? 0) > 0
            let isNullable = (row["notnull"]?.integerValue ?? 0) == 0
            let defaultValue = row["dflt_value"]?.textValue

            return ColumnInfo(
                name: name,
                type: type,
                isPrimaryKey: isPrimaryKey,
                isNullable: isNullable,
                defaultValue: defaultValue
            )
        }

        // Get foreign keys
        let fkResults = try connection.query("PRAGMA foreign_key_list('\(escapeSQLIdentifier(table))')")

        let foreignKeys = fkResults.compactMap { row -> ForeignKeyInfo? in
            guard case .text(let fromColumn) = row["from"],
                  case .text(let toTable) = row["table"],
                  case .text(let toColumn) = row["to"] else { return nil }

            return ForeignKeyInfo(
                column: fromColumn,
                referencedTable: toTable,
                referencedColumn: toColumn
            )
        }

        // Get indexes
        let indexResults = try connection.query("PRAGMA index_list('\(escapeSQLIdentifier(table))')")

        var indexes: [IndexInfo] = []
        for row in indexResults {
            guard case .text(let name) = row["name"] else { continue }
            let isUnique = (row["unique"]?.integerValue ?? 0) > 0

            // Get columns for this index
            let indexInfoResults = try connection.query("PRAGMA index_info('\(escapeSQLIdentifier(name))')")
            let indexColumns = indexInfoResults.compactMap { $0["name"]?.textValue }

            indexes.append(IndexInfo(name: name, isUnique: isUnique, columns: indexColumns))
        }

        return TableSchema(
            tableName: table,
            columns: columns,
            foreignKeys: foreignKeys,
            indexes: indexes
        )
    }

    // MARK: - Read Operations

    public func records(
        in table: String,
        offset: Int,
        limit: Int,
        orderBy: String?,
        ascending: Bool
    ) async throws -> [DatabaseRecord] {
        var sql = "SELECT * FROM \"\(escapeSQLIdentifier(table))\""

        if let orderColumn = orderBy {
            sql += " ORDER BY \"\(escapeSQLIdentifier(orderColumn))\" \(ascending ? "ASC" : "DESC")"
        }

        sql += " LIMIT \(limit) OFFSET \(offset)"

        let schema = try await schema(for: table)
        let primaryKeyColumn = schema.primaryKeyColumn?.name

        let results = try connection.query(sql)

        return results.map { row in
            let primaryKey = primaryKeyColumn.flatMap { row[$0] }
            return DatabaseRecord(
                tableName: table,
                primaryKey: primaryKey,
                primaryKeyColumn: primaryKeyColumn,
                values: row
            )
        }
    }

    public func recordCount(in table: String) async throws -> Int {
        let sql = "SELECT COUNT(*) as count FROM \"\(escapeSQLIdentifier(table))\""
        let results = try connection.query(sql)
        return Int(results.first?["count"]?.integerValue ?? 0)
    }

    public func record(in table: String, primaryKey: DatabaseValue) async throws -> DatabaseRecord? {
        let schema = try await schema(for: table)
        guard let pkColumn = schema.primaryKeyColumn else {
            throw DatabaseBrowserError.invalidPrimaryKey
        }

        let sql = "SELECT * FROM \"\(escapeSQLIdentifier(table))\" WHERE \"\(escapeSQLIdentifier(pkColumn.name))\" = ?"
        let results = try connection.query(sql, parameters: [primaryKey.anyValue])

        return results.first.map { row in
            DatabaseRecord(
                tableName: table,
                primaryKey: primaryKey,
                primaryKeyColumn: pkColumn.name,
                values: row
            )
        }
    }

    // MARK: - Write Operations

    public func insert(into table: String, values: [String: DatabaseValue]) async throws -> DatabaseRecord {
        let columns = values.keys.map { "\"\(escapeSQLIdentifier($0))\"" }.joined(separator: ", ")
        let placeholders = values.keys.map { _ in "?" }.joined(separator: ", ")
        let sql = "INSERT INTO \"\(escapeSQLIdentifier(table))\" (\(columns)) VALUES (\(placeholders))"

        try connection.execute(sql, parameters: Array(values.values.map { $0.anyValue }))

        let rowId = connection.lastInsertRowID

        // Fetch the inserted record
        let schema = try await schema(for: table)
        if let pkColumn = schema.primaryKeyColumn {
            let fetchSQL = "SELECT * FROM \"\(escapeSQLIdentifier(table))\" WHERE \"\(escapeSQLIdentifier(pkColumn.name))\" = ?"
            let results = try connection.query(fetchSQL, parameters: [rowId])
            if let row = results.first {
                return DatabaseRecord(
                    tableName: table,
                    primaryKey: .integer(rowId),
                    primaryKeyColumn: pkColumn.name,
                    values: row
                )
            }
        }

        return DatabaseRecord(
            tableName: table,
            primaryKey: .integer(rowId),
            primaryKeyColumn: nil,
            values: values
        )
    }

    public func update(in table: String, primaryKey: DatabaseValue, values: [String: DatabaseValue]) async throws {
        let schema = try await schema(for: table)
        guard let pkColumn = schema.primaryKeyColumn else {
            throw DatabaseBrowserError.invalidPrimaryKey
        }

        let setClause = values.keys.map { "\"\(escapeSQLIdentifier($0))\" = ?" }.joined(separator: ", ")
        let sql = "UPDATE \"\(escapeSQLIdentifier(table))\" SET \(setClause) WHERE \"\(escapeSQLIdentifier(pkColumn.name))\" = ?"

        var parameters = Array(values.values.map { $0.anyValue })
        parameters.append(primaryKey.anyValue)

        try connection.execute(sql, parameters: parameters)

        if connection.changesCount == 0 {
            throw DatabaseBrowserError.recordNotFound
        }
    }

    public func delete(from table: String, primaryKey: DatabaseValue) async throws {
        let schema = try await schema(for: table)
        guard let pkColumn = schema.primaryKeyColumn else {
            throw DatabaseBrowserError.invalidPrimaryKey
        }

        let sql = "DELETE FROM \"\(escapeSQLIdentifier(table))\" WHERE \"\(escapeSQLIdentifier(pkColumn.name))\" = ?"
        try connection.execute(sql, parameters: [primaryKey.anyValue])

        if connection.changesCount == 0 {
            throw DatabaseBrowserError.recordNotFound
        }
    }

    // MARK: - Query Operations

    public func executeQuery(_ sql: String) async throws -> QueryResult {
        try connection.executeWithResult(sql)
    }

    // MARK: - Private Helpers

    /// Escapes a SQL identifier to prevent injection.
    private func escapeSQLIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "\"", with: "\"\"")
    }

    /// Detects the database type based on table naming conventions.
    private static func detectDatabaseType(connection: SQLiteConnection) throws -> DatabaseType {
        // Check for CoreData tables (Z-prefixed)
        let coreDataCheck = try connection.query(
            "SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name LIKE 'Z%'"
        )
        if let count = coreDataCheck.first?["count"]?.integerValue, count > 0 {
            // Also check for CoreData metadata table
            let metadataCheck = try connection.query(
                "SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name = 'Z_METADATA'"
            )
            if let metaCount = metadataCheck.first?["count"]?.integerValue, metaCount > 0 {
                return .coreData
            }
        }

        // Check for SwiftData tables
        let swiftDataCheck = try connection.query(
            "SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND (name LIKE 'SWIFT%' OR name LIKE 'Z_%')"
        )
        if let count = swiftDataCheck.first?["count"]?.integerValue, count > 0 {
            // SwiftData uses similar naming to CoreData but may have different patterns
            // Check for SwiftData-specific metadata
            let modelCheck = try connection.query(
                "SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name = 'Z_MODELCACHE'"
            )
            if let modelCount = modelCheck.first?["count"]?.integerValue, modelCount > 0 {
                return .swiftData
            }
        }

        return .sqlite
    }
}
#endif
