//
//  DatabaseBrowser.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// A utility class for discovering and browsing databases in the app's sandbox.
///
/// `DatabaseBrowser` provides automatic discovery of SQLite databases (including
/// CoreData and SwiftData stores) in the app's container, as well as support for
/// custom database adapters.
///
/// ## Database Discovery
///
/// The browser automatically scans common locations for SQLite databases:
/// - `Library/Application Support/`
/// - `Documents/`
/// - `Library/`
///
/// ## Custom Adapters
///
/// Register custom adapters for third-party databases:
///
/// ```swift
/// Scyther.database.registerAdapter(MyRealmAdapter())
/// ```
@MainActor
public final class DatabaseBrowser: Sendable {
    /// The shared singleton instance.
    public static let instance = DatabaseBrowser()

    /// Registered custom database adapters.
    nonisolated(unsafe) private var customAdapters: [any DatabaseBrowserAdapter] = []

    /// Lock for thread-safe adapter access.
    private let adaptersLock = NSLock()

    /// The file manager for discovering databases.
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Adapter Registration

    /// Registers a custom database adapter.
    ///
    /// Use this to add support for third-party databases like Realm or Firebase.
    /// If an adapter with the same identifier already exists, it will be replaced.
    ///
    /// ```swift
    /// let realmAdapter = RealmDatabaseAdapter(realm: myRealm)
    /// DatabaseBrowser.instance.registerAdapter(realmAdapter)
    /// ```
    ///
    /// - Parameter adapter: The adapter to register.
    public nonisolated func registerAdapter(_ adapter: any DatabaseBrowserAdapter) {
        adaptersLock.lock()
        defer { adaptersLock.unlock() }

        customAdapters.removeAll { $0.identifier == adapter.identifier }
        customAdapters.append(adapter)
    }

    /// Removes a registered adapter by its identifier.
    ///
    /// - Parameter identifier: The identifier of the adapter to remove.
    public nonisolated func removeAdapter(withIdentifier identifier: String) {
        adaptersLock.lock()
        defer { adaptersLock.unlock() }

        customAdapters.removeAll { $0.identifier == identifier }
    }

    /// Returns all registered custom adapters.
    public nonisolated var registeredAdapters: [any DatabaseBrowserAdapter] {
        adaptersLock.lock()
        defer { adaptersLock.unlock() }

        return customAdapters
    }

    // MARK: - Database Discovery

    /// Discovers all available databases.
    ///
    /// This includes both automatically discovered SQLite databases and
    /// any registered custom adapters.
    ///
    /// - Returns: An array of discovered databases.
    public func discoverDatabases() async -> [DatabaseInfo] {
        var databases: [DatabaseInfo] = []

        // Search common locations for SQLite databases
        let searchPaths = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        for path in searchPaths {
            databases.append(contentsOf: await findSQLiteDatabases(in: path))
        }

        // Add custom adapters
        let adapters = registeredAdapters
        for adapter in adapters {
            var fileSize: Int64?
            var modDate: Date?

            if let path = adapter.filePath {
                let attributes = try? fileManager.attributesOfItem(atPath: path)
                fileSize = attributes?[.size] as? Int64
                modDate = attributes?[.modificationDate] as? Date
            }

            databases.append(DatabaseInfo(
                name: adapter.displayName,
                type: adapter.databaseType,
                path: adapter.filePath,
                fileSize: fileSize,
                modificationDate: modDate,
                adapter: adapter
            ))
        }

        // Sort by name
        return databases.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private Discovery Methods

    /// Finds SQLite databases in a directory.
    private func findSQLiteDatabases(in directory: URL) async -> [DatabaseInfo] {
        var results: [DatabaseInfo] = []

        // Collect file URLs synchronously first
        let fileURLs = collectSQLiteFileURLs(in: directory)

        // Process each URL asynchronously
        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()

            // Check for SQLite files by extension
            if ext == "sqlite" || ext == "sqlite3" || ext == "db" {
                if let info = await createDatabaseInfo(from: fileURL) {
                    results.append(info)
                }
            }

            // Check for CoreData stores (often have .sqlite extension but may have others)
            if ext == "store" || fileURL.lastPathComponent.contains(".sqlite") {
                if let info = await createDatabaseInfo(from: fileURL) {
                    // Avoid duplicates
                    if !results.contains(where: { $0.path == info.path }) {
                        results.append(info)
                    }
                }
            }
        }

        return results
    }

    /// Collects potential SQLite file URLs synchronously.
    private func collectSQLiteFileURLs(in directory: URL) -> [URL] {
        var fileURLs: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return fileURLs }

        while let element = enumerator.nextObject() {
            guard let fileURL = element as? URL else { continue }

            // Skip directories
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()

            // Only include potential database files
            if ext == "sqlite" || ext == "sqlite3" || ext == "db" || ext == "store" || fileURL.lastPathComponent.contains(".sqlite") {
                fileURLs.append(fileURL)
            }
        }

        return fileURLs
    }

    /// Creates a DatabaseInfo from a file URL.
    private func createDatabaseInfo(from url: URL) async -> DatabaseInfo? {
        do {
            let adapter = try SQLiteAdapter(path: url.path)

            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int64
            let modDate = attributes?[.modificationDate] as? Date

            return DatabaseInfo(
                name: url.lastPathComponent,
                type: adapter.databaseType,
                path: url.path,
                fileSize: size,
                modificationDate: modDate,
                adapter: adapter
            )
        } catch {
            // Failed to open as SQLite database
            return nil
        }
    }
}
#endif
