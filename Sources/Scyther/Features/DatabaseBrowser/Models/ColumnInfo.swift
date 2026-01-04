//
//  ColumnInfo.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// Metadata about a database column.
///
/// This struct describes the schema of a single column in a database table,
/// including its type, constraints, and default value.
public struct ColumnInfo: Identifiable, Sendable {
    /// Unique identifier for this column.
    public let id: UUID

    /// The name of the column.
    public let name: String

    /// The data type of the column (e.g., "INTEGER", "TEXT", "BLOB").
    public let type: String

    /// Whether this column is part of the primary key.
    public let isPrimaryKey: Bool

    /// Whether this column allows NULL values.
    public let isNullable: Bool

    /// The default value for this column, if any.
    public let defaultValue: String?

    /// Creates a new column info instance.
    ///
    /// - Parameters:
    ///   - name: The name of the column.
    ///   - type: The data type of the column.
    ///   - isPrimaryKey: Whether this is a primary key column. Defaults to `false`.
    ///   - isNullable: Whether NULL values are allowed. Defaults to `true`.
    ///   - defaultValue: The default value. Defaults to `nil`.
    public init(
        name: String,
        type: String,
        isPrimaryKey: Bool = false,
        isNullable: Bool = true,
        defaultValue: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.isPrimaryKey = isPrimaryKey
        self.isNullable = isNullable
        self.defaultValue = defaultValue
    }
}

/// Represents a foreign key relationship between tables.
///
/// Foreign keys define referential integrity constraints between
/// columns in different tables.
public struct ForeignKeyInfo: Identifiable, Sendable {
    /// Unique identifier for this foreign key.
    public let id: UUID

    /// The column in this table that references another table.
    public let column: String

    /// The table being referenced.
    public let referencedTable: String

    /// The column in the referenced table.
    public let referencedColumn: String

    /// Creates a new foreign key info instance.
    ///
    /// - Parameters:
    ///   - column: The local column name.
    ///   - referencedTable: The referenced table name.
    ///   - referencedColumn: The referenced column name.
    public init(column: String, referencedTable: String, referencedColumn: String) {
        self.id = UUID()
        self.column = column
        self.referencedTable = referencedTable
        self.referencedColumn = referencedColumn
    }
}

/// Represents a database index.
///
/// Indexes improve query performance by creating efficient
/// lookup structures for specified columns.
public struct IndexInfo: Identifiable, Sendable {
    /// Unique identifier for this index.
    public let id: UUID

    /// The name of the index.
    public let name: String

    /// Whether this index enforces uniqueness.
    public let isUnique: Bool

    /// The columns included in this index, if known.
    public let columns: [String]

    /// Creates a new index info instance.
    ///
    /// - Parameters:
    ///   - name: The name of the index.
    ///   - isUnique: Whether the index enforces uniqueness.
    ///   - columns: The columns in the index. Defaults to empty.
    public init(name: String, isUnique: Bool, columns: [String] = []) {
        self.id = UUID()
        self.name = name
        self.isUnique = isUnique
        self.columns = columns
    }
}
#endif
