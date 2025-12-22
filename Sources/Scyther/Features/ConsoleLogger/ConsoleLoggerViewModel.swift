//
//  ConsoleLoggerViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model for managing console logger state and operations.
///
/// `ConsoleLoggerViewModel` serves as the business logic layer for ``ConsoleLoggerView``,
/// handling log retrieval, auto-scroll preferences, and log management operations.
/// It maintains a published array of console log entries and automatically refreshes
/// when new logs are captured by the ``ConsoleLogger``.
///
/// ## Features
///
/// - **Real-time Log Updates**: Automatically fetches and publishes new console log entries
/// - **Auto-scroll Management**: Toggleable auto-scroll to follow new log entries as they arrive
/// - **Log Clearing**: Provides ability to clear all captured logs
/// - **Lifecycle Integration**: Uses the base ``ViewModel`` lifecycle hooks for efficient initialization
///
/// ## Usage
///
/// The view model is typically used as a `@StateObject` within ``ConsoleLoggerView``:
///
/// ```swift
/// struct ConsoleLoggerView: View {
///     @StateObject private var viewModel = ConsoleLoggerViewModel()
///
///     var body: some View {
///         List(viewModel.logs) { log in
///             Text(log.message)
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///         .toolbar {
///             Button("Clear") {
///                 viewModel.clearLogs()
///             }
///             Toggle("Auto-scroll", isOn: $viewModel.autoScroll)
///         }
///     }
/// }
/// ```
///
/// ## Performance Considerations
///
/// - All operations are marked with `@MainActor` to ensure UI updates happen on the main thread
/// - The ``refresh()`` method can be called from notification handlers to update logs in real-time
/// - Log entries are fetched from ``ConsoleLogger/instance`` which maintains an efficient rolling buffer
///
/// ## Topics
///
/// ### Published Properties
/// - ``logs``
/// - ``autoScroll``
///
/// ### Lifecycle Methods
/// - ``onFirstAppear()``
///
/// ### Log Management
/// - ``refresh()``
/// - ``clearLogs()``
@MainActor
class ConsoleLoggerViewModel: ViewModel {
    /// Array of console log entries to display.
    ///
    /// This published property contains all console log entries currently captured by the
    /// ``ConsoleLogger``. The array is automatically updated when ``refresh()`` is called,
    /// typically in response to new log notifications or initial view appearance.
    ///
    /// Each entry is a ``ConsoleLogEntry`` containing the timestamp, message, and source
    /// (stdout or stderr) of the captured log.
    @Published var logs: [ConsoleLogEntry] = []

    /// Whether to automatically scroll to the bottom when new logs arrive.
    ///
    /// When enabled, the console log view will automatically scroll to show the most recent
    /// log entry whenever new logs are added. This is useful for real-time monitoring scenarios
    /// where you want to follow the log stream as it updates.
    ///
    /// Defaults to `true`.
    @Published var autoScroll: Bool = true

    /// Called when the view first appears. Loads initial log data.
    ///
    /// This method overrides the base ``ViewModel/onFirstAppear()`` to perform the initial
    /// log data fetch when the console logger view is first displayed. It ensures that
    /// existing logs are loaded before the view becomes visible to the user.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await refresh()
    }

    /// Refreshes the logs from the console logger.
    ///
    /// Fetches the current log entries from ``ConsoleLogger/instance`` and updates the
    /// ``logs`` array. This method is typically called:
    /// - During initial view appearance via ``onFirstAppear()``
    /// - When a `.ConsoleLoggerDidLog` notification is received
    /// - When manually refreshing the log display
    ///
    /// The method is marked `@MainActor` to ensure the published ``logs`` property
    /// is updated on the main thread for proper SwiftUI updates.
    ///
    /// ## Example
    ///
    /// ```swift
    /// .onReceive(NotificationCenter.default.publisher(for: .ConsoleLoggerDidLog)) { _ in
    ///     Task { await viewModel.refresh() }
    /// }
    /// ```
    func refresh() async {
        logs = ConsoleLogger.instance.allLogs
    }

    /// Clears all console logs.
    ///
    /// Removes all log entries from both the ``ConsoleLogger`` singleton and the local
    /// ``logs`` array. This provides a clean slate for monitoring new log output.
    ///
    /// The operation is performed on the main actor to ensure thread-safe updates to
    /// both the console logger's internal buffer and the published logs property.
    ///
    /// ## Example
    ///
    /// ```swift
    /// Button(role: .destructive) {
    ///     viewModel.clearLogs()
    /// } label: {
    ///     Label("Clear Logs", systemImage: "trash")
    /// }
    /// ```
    func clearLogs() {
        ConsoleLogger.instance.clear()
        logs = []
    }
}
