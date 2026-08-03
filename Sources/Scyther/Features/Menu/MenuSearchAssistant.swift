//
//  MenuSearchAssistant.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import Foundation

/// A fuzzy-search tier that runs after exact/alias matching.
///
/// The menu's search pipeline is tiered by latency: ``MenuSearchIndex`` answers
/// synchronously on every keystroke, then ``MenuViewModel`` runs its assistants —
/// debounced, in order — and appends whatever they find that the synchronous tier
/// missed. An assistant that is unavailable on the current device (missing embedding
/// asset, no Apple Intelligence) returns an empty array rather than failing.
///
/// Built-in assistants, in pipeline order:
/// - ``MenuSearchEmbeddingMatcher`` — `NLEmbedding` sentence similarity
/// - `MenuSearchModelMatcher` — on-device Foundation Models (iOS 26+)
protocol MenuSearchAssistant: Sendable {
    /// The entries relevant to a query that plain text matching would miss.
    ///
    /// - Parameters:
    ///   - query: The user's trimmed, non-empty search text.
    ///   - entries: The full search index to choose from.
    /// - Returns: Matching entries, best match first. Empty when nothing matches or
    ///   the assistant is unavailable on this device. Callers deduplicate against
    ///   earlier tiers, so overlap with exact matches is harmless.
    func matches(for query: String, in entries: [MenuSearchEntry]) async -> [MenuSearchEntry]
}

enum MenuSearchAssistants {
    /// The assistants available on this device, in pipeline order: fast embedding
    /// similarity first, then the on-device language model where supported.
    static func available() -> [any MenuSearchAssistant] {
        var assistants: [any MenuSearchAssistant] = [MenuSearchEmbeddingMatcher()]
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            assistants.append(MenuSearchModelMatcher())
        }
        #endif
        return assistants
    }
}
