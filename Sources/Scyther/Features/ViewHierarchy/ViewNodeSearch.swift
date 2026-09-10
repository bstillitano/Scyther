//
//  ViewNodeSearch.swift
//  Scyther
//

#if !os(macOS)
import Foundation

/// Finds views in a snapshot by class name or by the text they carry.
///
/// Pure and separate from the page, because the rules here have right answers a test can check:
/// what matches, in what order, and what path is reported for a hit. A hit deep in a hierarchy
/// is useless without knowing where it lives, so every match carries its ancestor chain.
enum ViewNodeSearch {
    /// One search hit and the chain of ancestors above it.
    struct Match: Equatable, Sendable {
        /// The node that matched.
        let node: ViewNode

        /// The class names of the node's ancestors, root first, **excluding the node itself**.
        /// Empty when the root is the match.
        let path: [String]
    }

    /// Every node matching `query`, depth-first, parents before children.
    ///
    /// An empty or whitespace-only query returns nothing rather than everything: a blank search
    /// field means "not searching", and answering it with the entire tree would bury the page.
    ///
    /// Matching uses ``Swift/String/searchMatches(_:)``, the same rule the Cookie Browser and
    /// Environment Variables pages use, so a query behaves identically wherever it is typed.
    ///
    /// - Parameters:
    ///   - query: The user's search text.
    ///   - root: The snapshot's root node.
    /// - Returns: Matches in tree order.
    static func matches(for query: String, in root: ViewNode) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [Match] = []

        func walk(_ node: ViewNode, path: [String]) {
            if node.className.searchMatches(trimmed) || (node.text?.searchMatches(trimmed) ?? false) {
                results.append(Match(node: node, path: path))
            }
            let childPath = path + [node.className]
            for child in node.children { walk(child, path: childPath) }
        }

        walk(root, path: [])
        return results
    }
}
#endif
