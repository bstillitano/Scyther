//
//  ConsoleLoggerView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A SwiftUI view that displays captured console logs in a terminal-style interface.
///
/// `ConsoleLoggerView` provides a searchable list of console log entries with the following features:
/// - Terminal-style green-on-black color scheme
/// - Real-time log updates as new entries are captured
/// - Search functionality to filter logs
/// - Auto-scroll option to follow new logs
/// - Context menu for copying log entries
/// - Clear logs functionality
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     ConsoleLoggerView()
/// }
/// ```
struct ConsoleLoggerView: View {
    /// View model managing the console log state and business logic.
    @StateObject private var viewModel = ConsoleLoggerViewModel()

    /// Current search text for filtering logs.
    @State private var searchText: String = ""

    /// Terminal-style green color used throughout the UI.
    private static let terminalGreen = Color(red: 0.2, green: 1.0, blue: 0.2)

    var body: some View {
        Group {
            if viewModel.logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(Self.terminalGreen.opacity(0.6))
                    Text("No Logs")
                        .font(.headline)
                        .foregroundStyle(Self.terminalGreen)
                    Text("Console output will appear here")
                        .font(.subheadline)
                        .foregroundStyle(Self.terminalGreen.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredLogs) { log in
                                ConsoleLogRow(log: log, searchTerm: searchText)
                                    .id(log.id)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = log.message
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                        Button {
                                            UIPasteboard.general.string = "[\(log.formattedTimestamp)] \(log.message)"
                                        } label: {
                                            Label("Copy with Timestamp", systemImage: "doc.on.doc.fill")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .background(Color.black)
                    .scrollIndicators(.visible)
                    .onChange(of: viewModel.logs.count) { _ in
                        if viewModel.autoScroll, let lastLog = filteredLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search logs"
        )
        .navigationTitle("Console Logs")
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        viewModel.clearLogs()
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                    }

                    Divider()

                    Toggle("Auto-scroll", isOn: $viewModel.autoScroll)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ConsoleLoggerDidLog)) { _ in
            Task { await viewModel.refresh() }
        }
    }

    /// Returns filtered logs based on the current search text.
    ///
    /// If search text is empty, returns all logs. Otherwise, performs a case-insensitive
    /// search on the log message content.
    private var filteredLogs: [ConsoleLogEntry] {
        guard !searchText.isEmpty else { return viewModel.logs }
        return viewModel.logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
    }
}

/// A view that displays a single console log entry row.
///
/// Each row shows the timestamp and message text, with different styling for stdout and stderr:
/// - stdout logs are displayed in terminal green on a black background
/// - stderr logs are displayed in red on a light red background
struct ConsoleLogRow: View {
    /// The log entry to display.
    let log: ConsoleLogEntry

    /// Optional search term for highlighting (not currently used).
    let searchTerm: String

    /// Terminal-style green color for normal log text.
    private static let terminalGreen = Color(red: 0.2, green: 1.0, blue: 0.2)

    /// Returns the appropriate text color based on the log source.
    ///
    /// - Returns: Red for stderr, terminal green for stdout.
    private var textColor: Color {
        log.source == .stderr ? .red : Self.terminalGreen
    }

    /// Returns the appropriate background color based on the log source.
    ///
    /// - Returns: Light red background for stderr, clear for stdout.
    private var backgroundColor: Color {
        log.source == .stderr ? .red.opacity(0.15) : .clear
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(log.formattedTimestamp)
                .font(.caption.monospaced())
                .foregroundStyle(Self.terminalGreen.opacity(0.5))

            Text(log.message)
                .font(.caption.monospaced())
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(backgroundColor)
    }
}

/// View model for managing console logger state and operations.
///
/// This view model handles fetching logs from `ConsoleLogger`, managing the auto-scroll setting,
/// and providing actions for clearing logs.
class ConsoleLoggerViewModel: ViewModel {
    /// Array of console log entries to display.
    @Published var logs: [ConsoleLogEntry] = []

    /// Whether to automatically scroll to the bottom when new logs arrive.
    @Published var autoScroll: Bool = true

    /// Called when the view first appears. Loads initial log data.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await refresh()
    }

    /// Refreshes the logs from the console logger.
    ///
    /// Fetches the current log entries from `ConsoleLogger.instance` and updates the published logs array.
    @MainActor
    func refresh() async {
        logs = ConsoleLogger.instance.allLogs
    }

    /// Clears all console logs.
    ///
    /// Removes all log entries from both the console logger and the local logs array.
    @MainActor
    func clearLogs() {
        ConsoleLogger.instance.clear()
        logs = []
    }
}

#Preview {
    NavigationStack {
        ConsoleLoggerView()
    }
}
