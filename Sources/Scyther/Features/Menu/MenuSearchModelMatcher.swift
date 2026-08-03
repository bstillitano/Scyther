//
//  MenuSearchModelMatcher.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Intent-level search over the menu index using Apple's on-device language model.
///
/// Catches the phrasings the deterministic tiers can't — "why is my app slow"
/// landing on FPS Counter, "what backend am I pointed at" landing on Server
/// Configuration — by asking the Foundation Models framework to pick relevant
/// entries from the index catalogue via guided generation.
///
/// Requires iOS 26 and an Apple-Intelligence-enabled device; anywhere else
/// ``matches(for:in:)`` returns no results. Inference takes hundreds of
/// milliseconds, which is why ``MenuViewModel`` runs this tier debounced and last.
@available(iOS 26.0, *)
actor MenuSearchModelMatcher: MenuSearchAssistant {
    /// The identifiers the model selects from the catalogue.
    ///
    /// Not `private` — the `@Generable` macro's generated conformance extension
    /// cannot reference a private nested type.
    @Generable
    struct SelectedEntries {
        @Guide(description: "Identifiers of catalogue entries whose purpose matches the search query's intent. Empty if none are relevant.")
        var identifiers: [String]
    }

    func matches(for query: String, in entries: [MenuSearchEntry]) async -> [MenuSearchEntry] {
        guard SystemLanguageModel.default.availability == .available else { return [] }

        let catalogue = entries
            .map { "\($0.id): \($0.title) — \($0.breadcrumbText)" }
            .joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            You map a developer's search query to entries of an iOS debugging menu. \
            Given a query and a catalogue of entries (one "identifier: title — location" \
            per line), return the identifiers of entries a developer typing that query \
            is plausibly looking for. Match on purpose and intent, not just words. \
            Return few, highly relevant identifiers — or none.
            """)

        do {
            let response = try await session.respond(
                to: "Query: \(query)\n\nCatalogue:\n\(catalogue)",
                generating: SelectedEntries.self
            )
            let selected = Set(response.content.identifiers)
            return entries.filter { selected.contains($0.id) }
        } catch {
            return []
        }
    }
}
#endif
