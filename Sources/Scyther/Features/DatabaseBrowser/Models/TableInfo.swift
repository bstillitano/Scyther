//
//  TableInfo.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// Represents a table or view in a database.
///
/// Use this struct to display table listings and navigate to table contents.
public struct TableInfo: Identifiable, Hashable, Sendable {
    /// Unique identifier for this table.
    public let id: UUID

    /// The name of the table or view.
    public let name: String

    /// Whether this represents a view rather than a table.
    public let isView: Bool

    /// Creates a new table info instance.
    ///
    /// - Parameters:
    ///   - name: The name of the table or view.
    ///   - isView: Whether this is a view. Defaults to `false`.
    public init(name: String, isView: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isView = isView
    }
}

/// Detailed schema information for a database table.
///
/// This struct contains comprehensive metadata about a table's structure,
/// including columns, foreign keys, and indexes.
public struct TableSchema: Sendable {
    /// The name of the table.
    public let tableName: String

    /// The columns in this table.
    public let columns: [ColumnInfo]

    /// Foreign key relationships to other tables.
    public let foreignKeys: [ForeignKeyInfo]

    /// Indexes defined on this table.
    public let indexes: [IndexInfo]

    /// Creates a new table schema.
    ///
    /// - Parameters:
    ///   - tableName: The name of the table.
    ///   - columns: The columns in this table.
    ///   - foreignKeys: Foreign key relationships. Defaults to empty.
    ///   - indexes: Indexes on this table. Defaults to empty.
    public init(
        tableName: String,
        columns: [ColumnInfo],
        foreignKeys: [ForeignKeyInfo] = [],
        indexes: [IndexInfo] = []
    ) {
        self.tableName = tableName
        self.columns = columns
        self.foreignKeys = foreignKeys
        self.indexes = indexes
    }

    /// Returns the primary key column, if any.
    public var primaryKeyColumn: ColumnInfo? {
        columns.first { $0.isPrimaryKey }
    }
}
#endif
