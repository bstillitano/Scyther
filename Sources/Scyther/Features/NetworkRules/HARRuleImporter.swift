//
//  HARRuleImporter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// What one HAR document yielded when it was read.
///
/// The two numbers are reported separately because a developer who hands over a 300-entry capture
/// and gets 297 overrides needs to know which number is which.
struct HARImportResult: Equatable {
    /// One disabled mock override per entry that could be read, in document order.
    ///
    /// A rule carrying a response body carries the **bytes**, not an identifier: nothing is
    /// written until ``NetworkRuleStore`` takes the rules, so an import that is abandoned or
    /// refused leaves nothing on disk to reclaim.
    let rules: [NetworkRule]

    /// How many entries yielded no override at all — one that could not be decoded, or one whose
    /// URL could not be parsed into a host and a path.
    let skippedEntries: Int
}

/// Converts a HAR document into a set of disabled ``NetworkRule`` mock rules.
///
/// This closes the loop with ``NetworkLogHARBuilder``: a HAR exported from one session (or from
/// a teammate's Charles/Proxyman/Chrome DevTools capture) can be imported and replayed as mock
/// rules. Every imported rule arrives disabled, so importing a HAR can never silently change the
/// host app's behaviour — the developer opts each rule in explicitly.
///
/// ``HARRuleImporter`` performs no I/O of its own: a decoded response body travels on the rule
/// that answers with it, and ``NetworkRuleStore`` writes it when it takes the rule.
///
/// ## Usage
///
/// ```swift
/// let result = try HARRuleImporter.result(from: harData)
/// let stored = store.add(contentsOf: result.rules)
/// ```
enum HARRuleImporter {
    /// Builds one disabled mock rule per entry in a HAR document.
    ///
    /// The rule's name is `"<METHOD> <path>"`, and its match is exact on method, host and path —
    /// deliberately ignoring query, since a captured query string is incidental to the moment the
    /// entry was recorded and matching on it would make most imported rules never fire again.
    ///
    /// Entries are decoded **one at a time**, so one bad entry costs that entry and nothing else.
    /// A HAR in the wild is full of entries that do not fit the shape: an aborted request has no
    /// `response` at all, and a multipart upload as Chrome DevTools writes it carries a `postData`
    /// with `params` and no `text`. Decoding the document in a single call meant any one of those
    /// threw and the import produced nothing whatsoever. An entry whose `request.url` cannot be
    /// parsed into a host and a path is skipped for the same reason. Every skip is counted, so
    /// the caller can say how many entries were lost rather than quietly reporting a smaller
    /// number than the developer captured.
    ///
    /// The document itself must still be a HAR: a file with no `log.entries` array throws, since
    /// there is nothing there to be resilient about.
    ///
    /// - Parameter data: The raw bytes of a HAR 1.2 document, as produced by
    ///   ``NetworkLogHARBuilder`` or any other HAR-emitting tool.
    /// - Returns: The rules, and the number of entries that yielded none.
    /// - Throws: Whatever `JSONDecoder` throws when `data` is not a HAR document at all.
    static func result(from data: Data) throws -> HARImportResult {
        let document = try JSONDecoder().decode(LenientDocument.self, from: data)
        var rules: [NetworkRule] = []
        var skipped = 0
        for candidate in document.log.entries {
            guard let entry = candidate.entry, let rule = rule(for: entry) else {
                skipped += 1
                continue
            }
            rules.append(rule)
        }
        return HARImportResult(rules: rules, skippedEntries: skipped)
    }

    /// A HAR document whose entries are decoded independently of one another.
    ///
    /// Only the one field the importer reads is required, so a document that spells `creator` or
    /// `version` differently — or omits them — still imports.
    private struct LenientDocument: Decodable {
        /// The `log` object.
        let log: Log

        /// The `log` object's entry list.
        struct Log: Decodable {
            /// One wrapper per entry, each holding an entry or nothing.
            let entries: [LenientEntry]
        }
    }

    /// One HAR entry, or nothing when that entry does not fit ``HAREntry``.
    ///
    /// The failure is absorbed here rather than at the array, which is the whole point: a
    /// `[HAREntry]` throws on the first entry it cannot read and takes every other entry with it.
    private struct LenientEntry: Decodable {
        /// The entry, or `nil` when it could not be decoded.
        let entry: HAREntry?

        /// Decodes one entry, keeping `nil` instead of throwing.
        ///
        /// - Parameter decoder: The decoder positioned at one entry.
        init(from decoder: Decoder) throws {
            entry = try? HAREntry(from: decoder)
        }
    }

    /// Builds one disabled mock rule from a single HAR entry, or `nil` if its URL cannot be
    /// parsed.
    ///
    /// The method is uppercased once and reused for both the rule's name and its match, and an
    /// empty path (a URL with no trailing slash, e.g. `https://api.example.com`) is normalised to
    /// `"/"` so the rule is never named with a trailing space or matched against an empty path.
    ///
    /// The path is taken percent-encoded, because that is the form
    /// ``NetworkRuleMatch/matches(_:)`` compares against: a captured `/v1/a%2Fb` keeps its escaped
    /// separator rather than becoming a rule for the two segments `/v1/a/b`.
    ///
    /// - Parameter entry: The entry to convert.
    /// - Returns: The rule, or `nil` when the entry's URL has no host.
    private static func rule(for entry: HAREntry) -> NetworkRule? {
        guard let url = URL(string: entry.request.url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return nil
        }
        let method = entry.request.method.uppercased()
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath

        var mock = MockResponse(
            statusCode: entry.response.status,
            headers: headerDictionary(from: entry.response.headers)
        )
        mock.pendingBody = body(for: entry.response.content)

        return NetworkRule(
            name: "\(method) \(path)",
            isEnabled: false,
            match: NetworkRuleMatch(
                methods: [method],
                host: NetworkRulePattern(kind: .exact, value: host),
                path: NetworkRulePattern(kind: .exact, value: path),
                query: [:]
            ),
            actions: NetworkRuleActions(stub: .mock(mock))
        )
    }

    /// The bytes of a response body, or `nil` for an entry that has none.
    ///
    /// `encoding: "base64"` is a claim a HAR makes about its own text, and it is checked rather
    /// than believed:
    ///
    /// - Decoding ignores whitespace, so classic MIME base64 wrapped at 76 columns decodes rather
    ///   than being dropped in silence while the override is still created and still counted.
    ///   Scyther's own exporter emits one unbroken line, but Charles, Proxyman and DevTools are
    ///   the tools this importer exists for.
    /// - Text that is not base64-shaped is taken as the literal body it plainly is. A `{` cannot
    ///   appear in base64, so an entry that labels a JSON body `base64` is mislabelled, and
    ///   decoding it leniently would produce bytes that came from nowhere.
    /// - `content.size` breaks the remaining tie. Short text can be base64-shaped by accident —
    ///   `test` is four characters of the alphabet — so when the declared size is the length of
    ///   the literal and not the length of the decode, the literal is what the entry meant.
    ///
    /// - Parameter content: The entry's response content.
    /// - Returns: The body bytes, or `nil` when the entry has no body.
    private static func body(for content: HARContent) -> Data? {
        guard let text = content.text, !text.isEmpty else { return nil }
        let literal = Data(text.utf8)
        guard content.encoding?.lowercased() == "base64" else {
            return literal.isEmpty ? nil : literal
        }
        guard isBase64Shaped(text),
              let decoded = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              !decoded.isEmpty,
              !(content.size > 0 && decoded.count != content.size && literal.count == content.size) else {
            return literal.isEmpty ? nil : literal
        }
        return decoded
    }

    /// The base64 alphabet, without the padding character.
    private static let base64Alphabet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    )

    /// Whether `text` could be base64 at all, ignoring the whitespace a wrapped encoder inserts.
    ///
    /// - Parameter text: The `content.text` an entry declared as base64.
    /// - Returns: `true` when every non-whitespace character is in the alphabet, padding trails
    ///   rather than interrupts, and the length is a multiple of four.
    private static func isBase64Shaped(_ text: String) -> Bool {
        var count = 0
        var padding = 0
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            count += 1
            if scalar == "=" {
                padding += 1
                continue
            }
            guard padding == 0, base64Alphabet.contains(scalar) else { return false }
        }
        return count > 0 && count % 4 == 0 && padding <= 2
    }

    /// Flattens a HAR header list to a dictionary, keeping the last value for a repeated name.
    ///
    /// - Parameter headers: The entry's response headers.
    /// - Returns: The headers a mock can answer with.
    private static func headerDictionary(from headers: [HARNameValue]) -> [String: String] {
        Dictionary(headers.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
    }
}
