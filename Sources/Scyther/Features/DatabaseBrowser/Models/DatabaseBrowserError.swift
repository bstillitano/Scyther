//
//  DatabaseBrowserError.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// Errors that can occur during database operations.
///
/// These errors provide detailed information about what went wrong
/// during database browsing, querying, or CRUD operations.
public enum DatabaseBrowserError: LocalizedError, Sendable {
    /// Failed to connect to the database.
    case connectionFailed(String)

    /// A query failed to execute.
    case queryFailed(String)

    /// The specified table was not found.
    case tableNotFound(String)

    /// The specified record was not found.
    case recordNotFound

    /// Write operations are not supported by this adapter.
    case writeNotSupported

    /// The primary key value is invalid or missing.
    case invalidPrimaryKey

    /// A database constraint was violated.
    case constraintViolation(String)

    /// The SQL syntax is invalid.
    case invalidSQL(String)

    /// The database file could not be found.
    case fileNotFound(String)

    /// The database is locked by another process.
    case databaseLocked

    /// A general database error occurred.
    case general(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .tableNotFound(let name):
            return "Table not found: \(name)"
        case .recordNotFound:
            return "Record not found"
        case .writeNotSupported:
            return "Write operations are not supported by this database"
        case .invalidPrimaryKey:
            return "Invalid or missing primary key"
        case .constraintViolation(let message):
            return "Constraint violation: \(message)"
        case .invalidSQL(let message):
            return "Invalid SQL: \(message)"
        case .fileNotFound(let path):
            return "Database file not found: \(path)"
        case .databaseLocked:
            return "Database is locked by another process"
        case .general(let message):
            return message
        }
    }
}
#endif
