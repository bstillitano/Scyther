//
//  NetworkRuleStubKind.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// The three states of the editor's Stub picker: nothing, a canned response, or a local file.
///
/// ``NetworkRuleStub`` carries the configuration for whichever kind of stub an override serves,
/// which makes it unusable as a `Picker` selection. This enum is the same choices without the
/// payload, plus the "no stub at all" state the optional expresses in the model.
///
/// ## Usage
///
/// ```swift
/// Picker(localized("Stub"), selection: $viewModel.stubKind) {
///     ForEach(NetworkRuleStubKind.allCases) { Text($0.title).tag($0) }
/// }
/// ```
enum NetworkRuleStubKind: String, CaseIterable, Identifiable, Sendable {
    /// The request is performed; nothing answers it in its place.
    case none
    /// A canned response answers the request — ``NetworkRuleStub/mock(_:)``.
    case mock
    /// The contents of a local file answer the request — ``NetworkRuleStub/mapLocal(_:)``.
    case mapLocal

    /// A stable identity for `ForEach` and `Picker`.
    var id: String { rawValue }

    /// The localised label shown in the editor's stub picker.
    var title: String {
        switch self {
        case .none: return localized("None")
        case .mock: return localized("Mock Response")
        case .mapLocal: return localized("Map Local File")
        }
    }
}

internal extension NetworkRuleStub {
    /// This stub's kind, with its configuration discarded.
    var kind: NetworkRuleStubKind {
        switch self {
        case .mock: return .mock
        case .mapLocal: return .mapLocal
        }
    }
}

internal extension NetworkRuleActions {
    /// The localised names of everything this override does, in the order the editor lists them.
    ///
    /// An override carries several actions now, so a row cannot name its behaviour by switching
    /// over one value. Empty when the override does nothing at all, which the editor refuses to
    /// save but which a rule built in code may still be in the middle of.
    var titles: [String] {
        var titles: [String] = []
        if let stub { titles.append(stub.kind.title) }
        if rewriteHeaders != nil { titles.append(localized("Rewrite Headers")) }
        if condition != nil { titles.append(localized("Network Condition")) }
        return titles
    }

    /// The separator between the actions listed in a summary.
    ///
    /// A middle dot rather than a hyphen, matching the way iOS itself joins two facts on one
    /// line. Not localised: it is punctuation, not words.
    private static let summarySeparator = " \u{00B7} "

    /// ``titles`` on one line, for a row's subtitle.
    ///
    /// Reads `No actions` for an override that does nothing, which the editor refuses to save but
    /// which an override registered from code may still be — and which is worth saying plainly
    /// rather than leaving the subtitle blank.
    var summary: String {
        let titles = self.titles
        guard !titles.isEmpty else { return localized("No actions") }
        return titles.joined(separator: Self.summarySeparator)
    }
}
