//
//  CrashLogsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/12/2024.
//

#if !os(macOS)
import SwiftUI

/// A view displaying captured crash logs.
struct CrashLogsView: View {
    @StateObject private var viewModel = CrashLogsViewModel()
    @State private var searchText = ""

    private var filteredCrashes: [CrashLogEntry] {
        if searchText.isEmpty {
            return viewModel.crashes
        }
        return viewModel.crashes.filter { crash in
            crash.name.localizedCaseInsensitiveContains(searchText) ||
            (crash.reason?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if viewModel.crashes.isEmpty {
                emptyState
            } else {
                crashList
            }
        }
        .navigationTitle("Crash Logs")
        .searchable(text: $searchText, prompt: "Search crashes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !viewModel.crashes.isEmpty {
                    Button("Clear All", role: .destructive) {
                        viewModel.clearAll()
                    }
                }
            }
            #if DEBUG
            ToolbarItem(placement: .secondaryAction) {
                Button("Test Crash") {
                    viewModel.triggerTestCrash()
                }
            }
            #endif
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: CrashLogger.didRecordCrashNotification)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "No Crashes",
                systemImage: "checkmark.circle",
                description: Text("No crashes have been recorded. That's a good thing!")
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Crashes")
                    .font(.headline)
                Text("No crashes have been recorded. That's a good thing!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private var crashList: some View {
        List {
            ForEach(filteredCrashes) { crash in
                NavigationLink {
                    CrashDetailsView(crash: crash)
                } label: {
                    CrashRowView(crash: crash)
                }
            }
        }
    }
}

/// Row view for a single crash entry.
private struct CrashRowView: View {
    let crash: CrashLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(crash.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let reason = crash.reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(crash.formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("v\(crash.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// View model for the crash logs view.
@MainActor
class CrashLogsViewModel: ViewModel {
    @Published var crashes: [CrashLogEntry] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await refresh()
    }

    func refresh() async {
        crashes = CrashLogger.instance.allCrashes
    }

    func clearAll() {
        CrashLogger.instance.clear()
        crashes = []
    }

    #if DEBUG
    func triggerTestCrash() {
        CrashLogger.instance.triggerTestCrash()
    }
    #endif
}

#Preview {
    NavigationStack {
        CrashLogsView()
    }
}
#endif
