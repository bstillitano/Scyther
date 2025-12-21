//
//  CrashDetailsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/12/2024.
//

#if !os(macOS)
import SwiftUI

/// A detailed view for a single crash log entry.
struct CrashDetailsView: View {
    let crash: CrashLogEntry
    @State private var copied = false
    @State private var searchText = ""

    /// Stack trace entries filtered by search text.
    private var filteredStackTrace: [(index: Int, symbol: String)] {
        let indexed = crash.stackTrace.enumerated().map { (index: $0.offset, symbol: $0.element) }
        if searchText.isEmpty {
            return indexed
        }
        return indexed.filter { $0.symbol.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section("Exception") {
                LabeledContent("Name", value: crash.name)
                if let reason = crash.reason {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(reason)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Timestamp") {
                LabeledContent("Date", value: crash.formattedTimestamp)
            }

            Section("Environment") {
                LabeledContent("App Version", value: crash.appVersion)
                LabeledContent("Build Number", value: crash.buildNumber)
                LabeledContent("OS Version", value: crash.osVersion)
                LabeledContent("Device", value: crash.deviceModel)
            }

            Section {
                if crash.stackTrace.isEmpty {
                    Text("No stack trace available")
                        .foregroundStyle(.secondary)
                        .italic()
                } else if filteredStackTrace.isEmpty {
                    Text("No matching frames")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(filteredStackTrace, id: \.index) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.index)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            HighlightedText(
                                text: entry.symbol,
                                highlight: searchText
                            )
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Stack Trace")
                    Spacer()
                    if !crash.stackTrace.isEmpty && !searchText.isEmpty {
                        Text("\(filteredStackTrace.count) of \(crash.stackTrace.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Crash Details")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search stack trace")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    copyToClipboard()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }

                ShareLink(item: crash.fullReport) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = crash.fullReport
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                copied = false
            }
        }
    }
}

/// A text view that highlights occurrences of a search term.
private struct HighlightedText: View {
    /// The full text to display.
    let text: String

    /// The term to highlight within the text.
    let highlight: String

    var body: some View {
        Text(attributedString)
    }

    /// Builds an attributed string with highlighted matches.
    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)

        guard !highlight.isEmpty else {
            return attributedString
        }

        var searchStart = attributedString.startIndex
        while let range = attributedString[searchStart...].range(
            of: highlight,
            options: .caseInsensitive
        ) {
            attributedString[range].backgroundColor = .yellow.opacity(0.4)
            attributedString[range].foregroundColor = .primary
            searchStart = range.upperBound
        }

        return attributedString
    }
}

#Preview {
    NavigationStack {
        CrashDetailsView(crash: CrashLogEntry(
            id: UUID(),
            timestamp: Date(),
            name: "NSInvalidArgumentException",
            reason: "Attempted to insert nil object into array",
            stackTrace: [
                "0   CoreFoundation  0x00000001a1234567 __exceptionPreprocess + 220",
                "1   libobjc.A.dylib 0x00000001a0987654 objc_exception_throw + 60",
                "2   CoreFoundation  0x00000001a1345678 -[__NSArrayM insertObject:atIndex:] + 1084",
                "3   MyApp           0x0000000104567890 -[ViewController viewDidLoad] + 156",
                "4   UIKitCore       0x00000001a2345678 -[UIViewController _sendViewDidLoadWithAppearanceProxyObjectTaggingEnabled] + 100"
            ],
            appVersion: "1.0.0",
            buildNumber: "42",
            osVersion: "17.0",
            deviceModel: "iPhone"
        ))
    }
}
#endif
