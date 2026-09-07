//
//  PseudoLocalizationKey.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation

/// Recovers the catalog key from a `String.LocalizationValue`.
///
/// ``PseudoLocalizationMode/showsKeys`` needs the key, and `String.LocalizationValue` exposes no
/// public accessor for it — the type is deliberately opaque, being an interpolation-capturing
/// literal rather than a string.
///
/// Two ways out were considered. Resolving the value against a table that does not exist makes
/// Foundation fall back to the key, but it falls back to the key *formatted with the arguments*:
/// `Selected \(5) items` comes back as `Selected 5 items`, when the entry a developer has to go
/// and find in the catalog is `Selected %lld items`. Reflection returns the key verbatim, which is
/// the string that is actually useful, so reflection is what this uses — with the resolved value
/// as a fallback, because the layout of a Foundation struct is not a contract and a future OS is
/// entitled to change it.
///
/// ## Topics
///
/// ### Extracting
/// - ``extract(from:)``
/// - ``mirrorLabel``
enum PseudoLocalizationKey {
    /// The name of the stored property holding the key, as reflection reports it.
    static let mirrorLabel = "key"

    /// The catalog key behind a localisation value, or `nil` when it cannot be recovered.
    ///
    /// - Parameter value: The localisation value passed to ``localized(_:comment:override:)``.
    /// - Returns: The key, e.g. `"Selected %lld items"`, or `nil` if reflection finds no key.
    static func extract(from value: String.LocalizationValue) -> String? {
        for child in Mirror(reflecting: value).children where child.label == mirrorLabel {
            if let key = child.value as? String { return key }
        }
        return nil
    }
}
