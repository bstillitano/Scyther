//
//  TextReaderView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine

/// A SwiftUI view for displaying and searching through text content with highlighting and navigation.
///
/// `TextReaderView` provides a full-featured text viewer with:
/// - Search functionality with real-time highlighting
/// - Match navigation (previous/next)
/// - Match counter showing current position
/// - Text selection support
/// - Share functionality
/// - Monospaced font for code/structured data
///
/// ## Features
///
/// - **Search**: Debounced search with case-insensitive matching
/// - **Navigation**: Navigate through search matches with previous/next buttons
/// - **Highlighting**: Current match is highlighted differently from other matches
/// - **Performance**: Asynchronous text processing for large content
/// - **Sharing**: Built-in share sheet integration
///
/// ## Usage Example
///
/// ```swift
/// NavigationStack {
///     TextReaderView(
///         text: jsonResponse,
///         title: "API Response"
///     )
/// }
/// ```
///
/// ## Common Use Cases
///
/// - Displaying API responses
/// - Viewing log files
/// - Inspecting JSON/XML data
/// - Reading configuration files
/// - Debugging text output
struct TextReaderView: View {
    /// The text content to display and search through.
    let text: String

    /// The navigation title for the view.
    var title: String = "Text"

    /// The current search query entered by the user.
    @State private var searchText: String = ""

    /// The debounced search query used for actual searching.
    ///
    /// This is updated after a short delay to avoid excessive processing
    /// while the user is still typing.
    @State private var debouncedSearchText: String = ""

    /// Subject for publishing search text changes to be debounced.
    @State private var searchSubject = PassthroughSubject<String, Never>()

    /// Subscription to the debounced search subject.
    @State private var cancellable: AnyCancellable?

    /// The total number of matches found for the current search.
    @State private var matchCount: Int = 0

    /// The index of the currently highlighted match (0-based).
    @State private var currentMatchIndex: Int = 0

    /// Triggers scrolling to a specific match when set.
    @State private var scrollToMatch: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HighlightedTextView(
                    text: text,
                    searchText: debouncedSearchText,
                    currentMatchIndex: currentMatchIndex,
                    onMatchCountChanged: { matchCount = $0 }
                )
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
            }
            .onChange(of: scrollToMatch) { matchIndex in
                if let matchIndex {
                    withAnimation {
                        proxy.scrollTo("match-\(matchIndex)", anchor: .center)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !debouncedSearchText.isEmpty && matchCount > 0 {
                    SearchNavigationButtons(
                        currentMatch: currentMatchIndex + 1,
                        totalMatches: matchCount,
                        onPrevious: previousMatch,
                        onNext: nextMatch
                    )
                    .padding()
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search")
        .onChange(of: searchText) { newValue in
            searchSubject.send(newValue)
        }
        .onChange(of: debouncedSearchText) { _ in
            currentMatchIndex = 0
        }
        .onAppear {
            cancellable = searchSubject
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
                .sink { debouncedSearchText = $0 }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    /// Navigates to the next search match.
    ///
    /// Increments the current match index and scrolls to the next occurrence.
    /// Wraps around to the first match when reaching the end.
    private func nextMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
        scrollToMatch = currentMatchIndex
    }

    /// Navigates to the previous search match.
    ///
    /// Decrements the current match index and scrolls to the previous occurrence.
    /// Wraps around to the last match when at the beginning.
    private func previousMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        scrollToMatch = currentMatchIndex
    }
}

/// An internal view that performs the text highlighting and segmentation.
///
/// This view handles the heavy lifting of finding all matches and creating
/// text segments that can be individually styled. Processing is done
/// asynchronously to maintain UI responsiveness with large text content.
private struct HighlightedTextView: View {
    /// The full text to display.
    let text: String

    /// The search term to highlight.
    let searchText: String

    /// The index of the currently active match.
    let currentMatchIndex: Int

    /// Callback invoked when the total match count changes.
    let onMatchCountChanged: (Int) -> Void

    /// The computed text segments (matches and non-matches).
    @State private var segments: [TextSegment] = []

    var body: some View {
        Group {
            if segments.isEmpty || searchText.isEmpty {
                Text(text)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        if segment.isMatch {
                            Text(segment.text)
                                .foregroundColor(segment.matchIndex == currentMatchIndex ? .white : .accentColor)
                                .fontWeight(.bold)
                                .background(segment.matchIndex == currentMatchIndex ? Color.accentColor : Color.clear)
                                .id("match-\(segment.matchIndex ?? 0)")
                        } else {
                            Text(segment.text)
                        }
                    }
                }
            }
        }
        .task(id: searchText) {
            await computeSegments()
        }
    }

    /// Computes text segments by finding all search matches asynchronously.
    ///
    /// This method runs on a background thread to avoid blocking the UI when
    /// processing large amounts of text. Results are delivered back to the
    /// main thread when complete.
    ///
    /// The algorithm:
    /// 1. Performs case-insensitive search through the text
    /// 2. Creates segments for matched and non-matched portions
    /// 3. Assigns an index to each match for navigation
    /// 4. Updates the UI with the results
    private func computeSegments() async {
        guard !searchText.isEmpty else {
            await MainActor.run {
                segments = []
                onMatchCountChanged(0)
            }
            return
        }

        let search = searchText.lowercased()
        let source = text

        let result = await Task.detached(priority: .userInitiated) {
            var segs: [TextSegment] = []
            let lowercased = source.lowercased()
            var currentIndex = source.startIndex
            var matchIndex = 0

            while let range = lowercased.range(of: search, range: currentIndex..<source.endIndex) {
                // Add non-matching text before this match
                if currentIndex < range.lowerBound {
                    let before = String(source[currentIndex..<range.lowerBound])
                    segs.append(TextSegment(text: before, isMatch: false, matchIndex: nil))
                }

                // Add the match
                let match = String(source[range])
                segs.append(TextSegment(text: match, isMatch: true, matchIndex: matchIndex))
                matchIndex += 1

                currentIndex = range.upperBound
            }

            // Add remaining text
            if currentIndex < source.endIndex {
                let remaining = String(source[currentIndex..<source.endIndex])
                segs.append(TextSegment(text: remaining, isMatch: false, matchIndex: nil))
            }

            return (segs, matchIndex)
        }.value

        if !Task.isCancelled {
            await MainActor.run {
                segments = result.0
                onMatchCountChanged(result.1)
            }
        }
    }
}

/// Represents a segment of text that is either a match or non-match.
///
/// Used internally by ``HighlightedTextView`` to track which portions
/// of text should be highlighted.
private struct TextSegment {
    /// The text content of this segment.
    let text: String

    /// Whether this segment is a search match.
    let isMatch: Bool

    /// The index of this match (if it is a match).
    ///
    /// Used for navigation and highlighting the current match differently.
    let matchIndex: Int?
}

/// Navigation controls for moving between search matches.
///
/// Displays the current match position and provides previous/next buttons.
/// Uses glass effect styling on iOS 26+ for a modern appearance.
private struct SearchNavigationButtons: View {
    /// The 1-based index of the current match.
    let currentMatch: Int

    /// The total number of matches found.
    let totalMatches: Int

    /// Callback for navigating to the previous match.
    let onPrevious: () -> Void

    /// Callback for navigating to the next match.
    let onNext: () -> Void

    /// Namespace for glass effect union on iOS 26+.
    @Namespace private var namespace

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                HStack(spacing: 0) {
                    Button(action: onPrevious) {
                        Image(systemName: "chevron.up")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .glassEffectUnion(id: "search-nav", namespace: namespace)

                    Text("\(currentMatch) of \(totalMatches)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .glassEffect()
                        .glassEffectUnion(id: "search-nav", namespace: namespace)

                    Button(action: onNext) {
                        Image(systemName: "chevron.down")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .glassEffectUnion(id: "search-nav", namespace: namespace)
                }
            }
        } else {
            HStack(spacing: 8) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Text("\(currentMatch) of \(totalMatches)")
                    .font(.subheadline)
                    .monospacedDigit()

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TextReaderView(
            text: """
            {
                "name": "John Doe",
                "email": "john@example.com",
                "age": 30
            }
            """,
            title: "Response Body"
        )
    }
}
