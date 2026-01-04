//
//  DatabaseInfo.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// Represents a database available for browsing.
///
/// This struct contains metadata about a discovered database,
/// including its type, location, and the adapter used to access it.
public struct DatabaseInfo: Identifiable {
    /// Unique identifier for this database.
    public let id: UUID

    /// The display name of the database.
    public let name: String

    /// The type of database (SQLite, CoreData, SwiftData, custom).
    public let type: DatabaseType

    /// The file path to the database, if applicable.
    public let path: String?

    /// The size of the database file in bytes, if known.
    public let fileSize: Int64?

    /// The last modification date of the database, if known.
    public let modificationDate: Date?

    /// The adapter used to access this database.
    public let adapter: any DatabaseBrowserAdapter

    /// Creates a new database info instance.
    ///
    /// - Parameters:
    ///   - name: The display name.
    ///   - type: The database type.
    ///   - path: The file path.
    ///   - fileSize: The file size in bytes.
    ///   - modificationDate: The last modification date.
    ///   - adapter: The adapter for accessing this database.
    public init(
        name: String,
        type: DatabaseType,
        path: String?,
        fileSize: Int64?,
        modificationDate: Date?,
        adapter: any DatabaseBrowserAdapter
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.path = path
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.adapter = adapter
    }

    /// A formatted string for the file size.
    public var formattedFileSize: String? {
        guard let size = fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// A formatted string for the modification date.
    public var formattedModificationDate: String? {
        guard let date = modificationDate else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
#endif
