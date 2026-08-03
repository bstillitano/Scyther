//
//  MenuSearchEmbeddingMatcher.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import Foundation
import NaturalLanguage

/// Semantic search over the menu index using on-device sentence embeddings.
///
/// Scores the query against each entry's title and alias keywords with
/// `NLEmbedding`'s cosine distance and returns the closest entries under a
/// conservative threshold — close enough that "fake gps" can land on Location
/// Spoofer without littering results with weak associations.
///
/// The embedding asset is loaded lazily on first use and may be unavailable on
/// some devices or locales; the matcher then simply returns no results.
actor MenuSearchEmbeddingMatcher: MenuSearchAssistant {
    /// Cosine distances at or under this value count as a match. NLEmbedding's
    /// cosine distance ranges 0 (identical) to 2 (opposite); genuinely related
    /// short phrases typically score well under 1.
    private let threshold: Double

    /// The most results the matcher will return — semantic matches beyond the
    /// closest few are usually noise.
    private let limit: Int

    private lazy var embedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    /// Creates an embedding matcher.
    ///
    /// - Parameters:
    ///   - threshold: See ``threshold``. Defaults to 0.85.
    ///   - limit: See ``limit``. Defaults to 5.
    init(threshold: Double = 0.85, limit: Int = 5) {
        self.threshold = threshold
        self.limit = limit
    }

    func matches(for query: String, in entries: [MenuSearchEntry]) async -> [MenuSearchEntry] {
        guard let embedding else { return [] }
        let query = query.lowercased()

        let scored: [(entry: MenuSearchEntry, distance: Double)] = entries.compactMap { entry in
            let candidates = [entry.title] + entry.keywords
            let best = candidates
                .map { embedding.distance(between: query, and: $0.lowercased(), distanceType: .cosine) }
                .min() ?? .greatestFiniteMagnitude
            return best <= threshold ? (entry, best) : nil
        }

        return scored
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map(\.entry)
    }
}
