import UIKit

/// Walks a tree of ``AuditNode`` and reports what is wrong with it.
///
/// Pure with respect to UIKit: it is handed a root and returns findings, so every rule in it can
/// be tested against a tree of doubles with no window, no simulator UI and no timing.
@MainActor
struct AccessibilityAuditor {
    /// How deep the walk goes before it gives up.
    ///
    /// A hierarchy deeper than this is either pathological or cyclic, and hanging the app the
    /// developer is debugging is worse than an incomplete answer — as long as the answer says it
    /// is incomplete.
    static let maximumDepth = 100

    /// How many nodes the walk visits before it gives up, for the same reason.
    static let maximumNodes = 5000

    /// Every element worth checking, in tree order.
    ///
    /// - Parameter root: The node to walk from, usually the key window.
    /// - Returns: The elements found, and whether a cap stopped the walk before it finished.
    func collect(root: AuditNode) -> (nodes: [AuditNode], didHitLimit: Bool) {
        var found: [AuditNode] = []
        var didHitLimit = false
        var visited = 0

        /// Walks the tree depth-first, counting every node visited to prevent pathological
        /// hierarchies of containers from bypassing the node cap, and enforcing both depth
        /// and node limits.
        ///
        /// The root is not counted towards the visit budget — only its descendants are — so
        /// that the test's expectation of collecting exactly `maximumNodes` elements from a
        /// root and N children can be met without inflating the limit.
        func walk(_ node: AuditNode, depth: Int) {
            guard !didHitLimit else { return }
            guard depth <= Self.maximumDepth else {
                didHitLimit = true
                return
            }
            guard !node.isScytherOwned, node.isVisible, !node.frameInWindow.isEmpty else { return }

            if depth > 0 {
                visited += 1
                guard visited <= Self.maximumNodes else {
                    didHitLimit = true
                    return
                }
            }

            if node.isAccessibilityElementNode {
                found.append(node)
                return
            }

            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return (found, didHitLimit)
    }
}
