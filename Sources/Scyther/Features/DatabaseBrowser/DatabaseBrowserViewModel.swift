//
//  DatabaseBrowserViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
import Foundation

/// View model for the database browser list view.
///
/// Manages the discovery and display of available databases,
/// including both automatically discovered SQLite databases
/// and registered custom adapters.
@MainActor
final class DatabaseBrowserViewModel: ViewModel {
    // MARK: - Published Properties

    /// The list of discovered databases.
    @Published var databases: [DatabaseInfo] = []

    /// Whether the initial discovery is in progress.
    @Published var isLoading: Bool = false

    /// Whether an error occurred during discovery.
    @Published var showingError: Bool = false

    /// The error message to display.
    @Published var errorMessage: String = ""

    // MARK: - Lifecycle

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await refresh()
    }

    // MARK: - Actions

    /// Refreshes the list of discovered databases.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        databases = await DatabaseBrowser.instance.discoverDatabases()
    }

    // MARK: - Computed Properties

    /// Databases that are native SQLite-based (SQLite, CoreData, SwiftData).
    var nativeDatabases: [DatabaseInfo] {
        databases.filter { database in
            switch database.type {
            case .sqlite, .coreData, .swiftData:
                return true
            case .custom:
                return false
            }
        }
    }

    /// Databases from custom adapters (Realm, Firebase, etc.).
    var customDatabases: [DatabaseInfo] {
        databases.filter { database in
            if case .custom = database.type {
                return true
            }
            return false
        }
    }
}
#endif
