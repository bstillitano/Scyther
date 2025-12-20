//
//  HighlightingTextView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 27/6/2025.
//

import SwiftUI

/// A SwiftUI view that displays text with all matching substrings highlighted.
///
/// `HighlightingText` provides visual search result highlighting by coloring and
/// bolding all occurrences of a search term within the displayed text. The matching
/// is case-insensitive, making it ideal for search interfaces.
///
/// ## Features
///
/// - Case-insensitive substring matching
/// - Customizable highlight color
/// - Bold styling for matched text
/// - Efficient text composition using SwiftUI's Text concatenation
///
/// ## Usage Example
///
/// ```swift
/// HighlightingText(
///     "The quick brown fox jumps over the lazy dog",
///     substring: "fox",
///     highlightColor: .orange
/// )
/// ```
///
/// This will display the text with "fox" highlighted in orange and bold.
///
/// ## Search Interface Example
///
/// ```swift
/// struct SearchResultView: View {
///     let result: String
///     @State private var searchQuery: String = ""
///
///     var body: some View {
///         VStack {
///             TextField("Search", text: $searchQuery)
///             HighlightingText(result, substring: searchQuery)
///         }
///     }
/// }
/// ```
///
/// - Note: Available on iOS 15.0+ and macOS 12.0+
@available(iOS 15.0, macOS 12.0, *)
public struct HighlightingText: View {
    /// The full text string to display.
    let string: String

    /// The substring to search for and highlight within the text.
    ///
    /// If `nil` or empty, the text is displayed without any highlighting.
    /// Matching is case-insensitive.
    let substring: String?

    /// The color used to highlight matching substrings.
    ///
    /// Defaults to the system accent color for consistent theming.
    var highlightColor: Color = .accentColor

    /// Creates a new highlighting text view.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Highlight "Swift" in red
    /// HighlightingText(
    ///     "Swift is a powerful language",
    ///     substring: "swift",
    ///     highlightColor: .red
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - string: The full string to display
    ///   - substring: The substring to highlight (case-insensitive). Pass `nil` for no highlighting
    ///   - highlightColor: The color to use for highlighting matches. Defaults to `.accentColor`
    public init(_ string: String, substring: String?, highlightColor: Color = .accentColor) {
        self.string = string
        self.substring = substring
        self.highlightColor = highlightColor
    }

    public var body: some View {
        highlightedText()
    }

    /// Generates a `Text` view with all matching substrings highlighted.
    ///
    /// This method performs case-insensitive search through the string and builds
    /// a composite `Text` view where matching portions are colored and bolded.
    ///
    /// - Returns: A `Text` view with highlighted matches, or the original text if no substring is provided
    private func highlightedText() -> Text {
        guard let substring, !substring.isEmpty else {
            return Text(string)
        }

        let lowercasedFullText = string.lowercased()
        let lowercasedSubstring = substring.lowercased()

        var result = Text("")
        var currentIndex = string.startIndex

        while let range = lowercasedFullText.range(of: lowercasedSubstring, options: [], range: currentIndex..<string.endIndex) {
            let before = String(string[currentIndex..<range.lowerBound])
            let match = String(string[range])

            result = result + Text(before)
            result = result + Text(match)
                .foregroundColor(highlightColor)
                .bold()

            currentIndex = range.upperBound
        }

        // Append the remaining text
        let remaining = String(string[currentIndex..<string.endIndex])
        result = result + Text(remaining)

        return result
    }
}
