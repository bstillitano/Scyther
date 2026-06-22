//
//  GraphQLOperation.swift
//  Scyther
//

import Foundation

/// The kind of a GraphQL operation as declared by the leading keyword of its document.
enum GraphQLOperationType: String, Sendable {
    case query
    case mutation
    case subscription

    /// A capitalised label suitable for detail rows, e.g. "Query".
    var displayName: String { rawValue.capitalized }

    /// An uppercased label suitable for a list-row lozenge, e.g. "QUERY".
    var badgeText: String { rawValue.uppercased() }
}

/// A parsed representation of a GraphQL request body.
///
/// Use ``parse(body:url:)`` to interpret a request body. The parser is pure: it performs
/// no disk or network access and is safe to call on any thread.
struct GraphQLOperation {
    /// The resolved operation name. `"(anonymous)"` when the document has no name, or
    /// `"Batch (N operations)"` for batched requests.
    let operationName: String

    /// The operation type, or `nil` for batched requests.
    let type: GraphQLOperationType?

    /// Whether the request is a batched array of operations.
    let isBatch: Bool

    /// The number of operations (1 for a single operation).
    let batchCount: Int

    /// The raw `variables` object, if present, for structured browsing.
    let variables: [String: Any]?

    /// Parses `data` as a GraphQL request body.
    ///
    /// A request is treated as GraphQL when the JSON body contains a `query` string field,
    /// or when `url`'s path contains `graphql`/`gql` and the body is JSON.
    ///
    /// - Parameters:
    ///   - data: The raw request body.
    ///   - url: The request URL string, used for the path heuristic.
    /// - Returns: A parsed operation, or `nil` if the body is not GraphQL.
    static func parse(body data: Data?, url: String?) -> GraphQLOperation? {
        guard let data, !data.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let pathHint = urlHasGraphQLHint(url)

        // Batched operations: an array of operation objects.
        if let array = json as? [[String: Any]] {
            let queryCount = array.filter { $0["query"] is String }.count
            guard queryCount > 0 || pathHint else { return nil }
            let count = queryCount > 0 ? queryCount : array.count
            return GraphQLOperation(
                operationName: "Batch (\(count) operations)",
                type: nil,
                isBatch: true,
                batchCount: count,
                variables: nil
            )
        }

        // Single operation object.
        guard let object = json as? [String: Any] else { return nil }
        let query = object["query"] as? String
        guard query != nil || pathHint else { return nil }

        return GraphQLOperation(
            operationName: resolveName(explicit: object["operationName"] as? String, query: query),
            type: operationType(from: query),
            isBatch: false,
            batchCount: 1,
            variables: object["variables"] as? [String: Any]
        )
    }

    private static func urlHasGraphQLHint(_ url: String?) -> Bool {
        guard let url else { return false }
        let path = (URL(string: url)?.path ?? url).lowercased()
        return path.contains("graphql") || path.contains("gql")
    }

    private static func operationType(from query: String?) -> GraphQLOperationType? {
        guard let query else { return nil }
        switch firstKeyword(in: query) {
        case "mutation": return .mutation
        case "subscription": return .subscription
        default: return .query // explicit `query`, or shorthand `{ ... }`
        }
    }

    private static func resolveName(explicit: String?, query: String?) -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        if let parsed = parsedName(from: query) { return parsed }
        return "(anonymous)"
    }

    /// The lowercased leading keyword of the document, or `nil` for shorthand `{ ... }`.
    private static func firstKeyword(in query: String) -> String? {
        let trimmed = query.drop(while: { $0.isWhitespace })
        if trimmed.first == "{" { return nil }
        let letters = trimmed.prefix(while: { $0.isLetter })
        return letters.isEmpty ? nil : String(letters).lowercased()
    }

    /// The operation name declared after the leading keyword, e.g. `GetUser`.
    private static func parsedName(from query: String?) -> String? {
        guard let query else { return nil }
        var scanner = query.drop(while: { $0.isWhitespace })
        let keyword = scanner.prefix(while: { $0.isLetter })
        if ["query", "mutation", "subscription"].contains(String(keyword).lowercased()) {
            scanner = scanner.dropFirst(keyword.count).drop(while: { $0.isWhitespace })
        } else if scanner.first == "{" {
            return nil
        }
        let nameChars = scanner.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
        return nameChars.isEmpty ? nil : String(nameChars)
    }
}

extension GraphQLOperation: @unchecked Sendable { }
