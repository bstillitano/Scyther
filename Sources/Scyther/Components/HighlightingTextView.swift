//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 27/6/2025.
//

import SwiftUI

/// A SwiftUI view that displays a string with all matching substrings highlighted.
@available(iOS 15.0, macOS 12.0, *)
public struct HighlightingText: View {
    let string: String
    let substring: String?
    var highlightColor: Color = .accentColor

    /// Creates a new `HighlightingText` view that highlights all occurrences of a substring in the given text.
    ///
    /// - Parameters:
    ///   - string: The full string to display.
    ///   - substring: The substring to highlight. Matching is case-insensitive.
    ///   - highlightColor: The color to use for highlighting matches. Defaults to `.accentColor`.
    public init(_ string: String, substring: String?, highlightColor: Color = .accentColor) {
        self.string = string
        self.substring = substring
        self.highlightColor = highlightColor
    }

    public var body: some View {
        highlightedText()
    }

    /// Generates a `Text` view with all matching substrings highlighted.
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
