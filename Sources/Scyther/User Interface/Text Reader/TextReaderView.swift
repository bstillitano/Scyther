//
//  TextReaderView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Combine

struct TextReaderView: View {
    let text: String
    var title: String = "Text"

    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchSubject = PassthroughSubject<String, Never>()
    @State private var cancellable: AnyCancellable?
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
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
        }
        .safeAreaInset(edge: .bottom) {
            if !debouncedSearchText.isEmpty {
                HStack {
                    Text(matchCount > 0 ? "\(currentMatchIndex + 1) of \(matchCount)" : "No matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        previousMatch()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(matchCount == 0)

                    Button {
                        nextMatch()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(matchCount == 0)
                }
                .padding()
                .background(.bar)
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

    private func nextMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
        scrollToMatch = currentMatchIndex
    }

    private func previousMatch() {
        guard matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        scrollToMatch = currentMatchIndex
    }
}

private struct HighlightedTextView: View {
    let text: String
    let searchText: String
    let currentMatchIndex: Int
    let onMatchCountChanged: (Int) -> Void

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

private struct TextSegment {
    let text: String
    let isMatch: Bool
    let matchIndex: Int?
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
