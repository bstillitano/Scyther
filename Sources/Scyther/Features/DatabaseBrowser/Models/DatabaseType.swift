//
//  DatabaseType.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// The type of database being browsed.
///
/// This enum identifies the underlying database technology, which affects
/// how the database is displayed and what features are available.
public enum DatabaseType: Equatable, Sendable {
    /// A plain SQLite database file.
    case sqlite

    /// A CoreData persistent store (uses SQLite under the hood).
    case coreData

    /// A SwiftData persistent store (uses SQLite under the hood).
    case swiftData

    /// A custom database type provided by an external adapter.
    ///
    /// - Parameter name: The display name for this database type (e.g., "Realm", "Firebase").
    case custom(String)

    /// The human-readable display name for this database type.
    public var displayName: String {
        switch self {
        case .sqlite:
            return "SQLite"
        case .coreData:
            return "Core Data"
        case .swiftData:
            return "SwiftData"
        case .custom(let name):
            return name
        }
    }

    /// The SF Symbol icon name for this database type.
    public var iconName: String {
        switch self {
        case .sqlite:
            return "cylinder.fill"
        case .coreData:
            return "square.stack.3d.up.fill"
        case .swiftData:
            return "swift"
        case .custom:
            return "externaldrive.fill"
        }
    }
}
#endif
