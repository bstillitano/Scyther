//
//  HARRuleImporter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// Converts a HAR document into a set of disabled ``NetworkRule`` mock rules.
///
/// This closes the loop with ``NetworkLogHARBuilder``: a HAR exported from one session (or from
/// a teammate's Charles/Proxyman/Chrome DevTools capture) can be imported and replayed as mock
/// rules. Every imported rule arrives disabled, so importing a HAR can never silently change the
/// host app's behaviour — the developer opts each rule in explicitly.
///
/// ``HARRuleImporter`` performs no I/O of its own: response bodies are handed to a caller-supplied
/// `storeBody` closure, which stays free to persist them however it likes (``NetworkRuleStore``
/// in production, an in-memory array in tests).
///
/// ## Usage
///
/// ```swift
/// let rules = try HARRuleImporter.rules(from: harData) { body in
///     store.storeBody(body)
/// }
/// ```
enum HARRuleImporter {
    /// Builds one disabled mock rule per entry in a HAR document.
    ///
    /// The rule's name is `"<METHOD> <path>"`, and its match is exact on method, host and path —
    /// deliberately ignoring query, since a captured query string is incidental to the moment the
    /// entry was recorded and matching on it would make most imported rules never fire again.
    ///
    /// An entry whose `request.url` cannot be parsed into host and path components is skipped
    /// rather than failing the whole import, since one malformed entry in an otherwise-valid HAR
    /// should not discard every other entry.
    ///
    /// - Parameters:
    ///   - data: The raw bytes of a HAR 1.2 document, as produced by ``NetworkLogHARBuilder`` or
    ///     any other HAR-emitting tool.
    ///   - storeBody: Called with the decoded response body bytes for an entry that has one, and
    ///     expected to return the identifier under which those bytes are stored. Not called for
    ///     an entry with an empty or missing body.
    /// - Returns: One disabled ``NetworkRule`` per HAR entry with a parseable URL.
    /// - Throws: Whatever `JSONDecoder` throws when `data` is not a valid HAR document.
    static func rules(from data: Data, storeBody: (Data) -> UUID) throws -> [NetworkRule] {
        let har = try JSONDecoder().decode(HARLog.self, from: data)
        return har.log.entries.compactMap { rule(for: $0, storeBody: storeBody) }
    }

    /// Builds one disabled mock rule from a single HAR entry, or `nil` if its URL cannot be
    /// parsed.
    ///
    /// The method is uppercased once and reused for both the rule's name and its match, and an
    /// empty path (a URL with no trailing slash, e.g. `https://api.example.com`) is normalised to
    /// `"/"` so the rule is never named with a trailing space or matched against an empty path.
    private static func rule(for entry: HAREntry, storeBody: (Data) -> UUID) -> NetworkRule? {
        guard let url = URL(string: entry.request.url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return nil
        }
        let method = entry.request.method.uppercased()
        let path = components.path.isEmpty ? "/" : components.path

        let bodyID = bodyID(for: entry.response.content, storeBody: storeBody)
        let mock = MockResponse(
            statusCode: entry.response.status,
            headers: headerDictionary(from: entry.response.headers),
            bodyID: bodyID
        )

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

    /// Decodes a response body and stores it, or returns `nil` for an entry with no body.
    ///
    /// `storeBody` is only invoked when there are bytes to store, so an entry with an empty or
    /// missing body never touches the caller's storage.
    private static func bodyID(for content: HARContent, storeBody: (Data) -> UUID) -> UUID? {
        guard let text = content.text, !text.isEmpty else { return nil }
        let bodyData: Data?
        if content.encoding == "base64" {
            bodyData = Data(base64Encoded: text)
        } else {
            bodyData = Data(text.utf8)
        }
        guard let bodyData, !bodyData.isEmpty else { return nil }
        return storeBody(bodyData)
    }

    /// Flattens a HAR header list to a dictionary, keeping the last value for a repeated name.
    private static func headerDictionary(from headers: [HARNameValue]) -> [String: String] {
        Dictionary(headers.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
    }
}
