//
//  CrashLogsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/12/2024.
//

#if !os(macOS)
import Foundation

/// View model for managing the crash logs list view.
///
/// `CrashLogsViewModel` handles fetching crash logs from ``CrashLogger``,
/// managing the list state, and providing actions for clearing logs and
/// testing crash capture functionality.
///
/// ## Features
/// - Loads crash logs from persistent storage
/// - Supports clearing all crash logs
/// - Provides test crash functionality (debug builds only)
/// - Responds to crash log update notifications
///
/// ## Usage
/// ```swift
/// @StateObject private var viewModel = CrashLogsViewModel()
///
/// // Access crashes
/// ForEach(viewModel.crashes) { crash in
///     Text(crash.name)
/// }
///
/// // Clear all logs
/// viewModel.clearAll()
/// ```
///
/// ## Topics
///
/// ### Managing Crash Logs
/// - ``crashes``
/// - ``refresh()``
/// - ``clearAll()``
///
/// ### Testing
/// - ``triggerTestCrash()``
@MainActor
class CrashLogsViewModel: ViewModel {
    // MARK: - Published Properties

    /// The list of captured crash logs, newest first.
    ///
    /// This array is populated from ``CrashLogger/allCrashes`` and updates
    /// when ``refresh()`` is called or when the view first appears.
    @Published var crashes: [CrashLogEntry] = []

    // MARK: - Lifecycle

    /// Called when the view first appears.
    ///
    /// Loads the initial set of crash logs from storage.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await refresh()
    }

    // MARK: - Public Methods

    /// Refreshes the crash logs from storage.
    ///
    /// Call this method to reload crash logs after external changes
    /// or when receiving a ``CrashLogger/didRecordCrashNotification``.
    func refresh() async {
        crashes = CrashLogger.instance.allCrashes
    }

    /// Clears all stored crash logs.
    ///
    /// This removes all crash logs from persistent storage and updates
    /// the UI to show an empty state. This action cannot be undone.
    func clearAll() {
        CrashLogger.instance.clear()
        crashes = []
    }

    // MARK: - Testing Support

    #if DEBUG
    /// Triggers a test crash for development purposes.
    ///
    /// This method raises an `NSException` to test the crash logging
    /// functionality. The crash will be captured and visible on the
    /// next app launch.
    ///
    /// - Warning: This will crash the application immediately.
    ///   Only available in debug builds.
    func triggerTestCrash() {
        CrashLogger.instance.triggerTestCrash()
    }
    #endif
}
#endif
