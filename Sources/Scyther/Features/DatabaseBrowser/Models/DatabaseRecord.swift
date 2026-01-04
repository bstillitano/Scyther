//
//  DatabaseRecord.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// Represents a single database record/row.
///
/// A database record contains the values for all columns in a table row,
/// along with metadata about which table it belongs to and its primary key.
public struct DatabaseRecord: Identifiable, Sendable {
    /// Unique identifier for this record instance.
    public let id: UUID

    /// The name of the table this record belongs to.
    public let tableName: String

    /// The primary key value for this record, if available.
    public let primaryKey: DatabaseValue?

    /// The name of the primary key column, if known.
    public let primaryKeyColumn: String?

    /// The column values for this record.
    public let values: [String: DatabaseValue]

    /// Creates a new database record.
    ///
    /// - Parameters:
    ///   - tableName: The table name.
    ///   - primaryKey: The primary key value.
    ///   - primaryKeyColumn: The primary key column name.
    ///   - values: The column values.
    public init(
        tableName: String,
        primaryKey: DatabaseValue? = nil,
        primaryKeyColumn: String? = nil,
        values: [String: DatabaseValue]
    ) {
        self.id = UUID()
        self.tableName = tableName
        self.primaryKey = primaryKey
        self.primaryKeyColumn = primaryKeyColumn
        self.values = values
    }

    /// Returns a display string for a column value.
    ///
    /// - Parameter column: The column name.
    /// - Returns: A formatted string representation of the value.
    public func displayValue(for column: String) -> String {
        guard let value = values[column] else { return "NULL" }
        return value.displayString
    }

    /// Returns the sorted column names.
    public var sortedColumnNames: [String] {
        values.keys.sorted()
    }
}

/// A type-safe wrapper for database values.
///
/// This enum represents all possible value types that can be stored
/// in a SQLite database column.
public enum DatabaseValue: Sendable, Equatable, CustomStringConvertible {
    /// A NULL value.
    case null

    /// An integer value.
    case integer(Int64)

    /// A floating-point value.
    case real(Double)

    /// A text/string value.
    case text(String)

    /// A binary blob value.
    case blob(Data)

    /// Creates a database value from an Any value.
    ///
    /// - Parameter value: The value to convert.
    public init(from value: Any?) {
        guard let value = value else {
            self = .null
            return
        }

        switch value {
        case is NSNull:
            self = .null
        case let int as Int:
            self = .integer(Int64(int))
        case let int64 as Int64:
            self = .integer(int64)
        case let int32 as Int32:
            self = .integer(Int64(int32))
        case let double as Double:
            self = .real(double)
        case let float as Float:
            self = .real(Double(float))
        case let string as String:
            self = .text(string)
        case let data as Data:
            self = .blob(data)
        case let bool as Bool:
            self = .integer(bool ? 1 : 0)
        default:
            self = .text(String(describing: value))
        }
    }

    /// A display-friendly string representation of the value.
    public var displayString: String {
        switch self {
        case .null:
            return "NULL"
        case .integer(let value):
            return String(value)
        case .real(let value):
            return String(format: "%.6g", value)
        case .text(let value):
            return value
        case .blob(let data):
            return "<\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .memory))>"
        }
    }

    public var description: String {
        displayString
    }

    /// The underlying value as Any for compatibility.
    public var anyValue: Any {
        switch self {
        case .null:
            return NSNull()
        case .integer(let value):
            return value
        case .real(let value):
            return value
        case .text(let value):
            return value
        case .blob(let value):
            return value
        }
    }

    /// Whether this value is NULL.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// The value as an optional Int64.
    public var integerValue: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    /// The value as an optional Double.
    public var realValue: Double? {
        if case .real(let value) = self { return value }
        return nil
    }

    /// The value as an optional String.
    public var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    /// The value as optional Data.
    public var blobValue: Data? {
        if case .blob(let value) = self { return value }
        return nil
    }
}
#endif
