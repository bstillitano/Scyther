//
//  ConsoleLoggerView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct ConsoleLoggerView: View {
    @StateObject private var viewModel = ConsoleLoggerViewModel()
    @State private var searchText: String = ""

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

    private var filteredLogs: [ConsoleLogEntry] {
        guard !searchText.isEmpty else { return viewModel.logs }
        return viewModel.logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
    }
}

struct ConsoleLogRow: View {
    let log: ConsoleLogEntry
    let searchTerm: String

    private static let terminalGreen = Color(red: 0.2, green: 1.0, blue: 0.2)

    private var textColor: Color {
        log.source == .stderr ? .red : Self.terminalGreen
    }

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

class ConsoleLoggerViewModel: ViewModel {
    @Published var logs: [ConsoleLogEntry] = []
    @Published var autoScroll: Bool = true

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await refresh()
    }

    @MainActor
    func refresh() async {
        logs = ConsoleLogger.instance.allLogs
    }

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
