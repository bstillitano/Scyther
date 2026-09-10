//
//  ViewHierarchySnapshot.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// One walk of a view hierarchy, and the means to get back to a live view from it.
///
/// The tree itself is ``ViewNode`` values holding no references. This type owns the one bridge
/// back to UIKit that the inspector needs — the thumbnail — and keeps it **weak**, so a snapshot
/// left open on a screen the user has since navigated away from does not keep that screen alive.
/// A node whose view has gone resolves to `nil`, and the detail page reports that rather than
/// rendering an empty box.
@MainActor
final class ViewHierarchySnapshot {
    /// The root of the walked tree.
    let root: ViewNode

    /// When the walk ran. The page shows this, because a snapshot that does not say it is a
    /// snapshot is a lie.
    let takenAt: Date

    /// How many nodes the tree holds, including the root.
    let nodeCount: Int

    /// Weak boxes keyed by node identity.
    private let views: [ObjectIdentifier: WeakView]

    /// A weak reference in a box, so it can live in a dictionary.
    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - root: The walked tree.
    ///   - views: Every node's identity mapped to its view.
    ///   - takenAt: When the walk ran. Defaults to now.
    init(root: ViewNode, views: [ObjectIdentifier: UIView], takenAt: Date = Date()) {
        self.root = root
        self.takenAt = takenAt
        self.views = views.mapValues(WeakView.init)

        func count(_ node: ViewNode) -> Int {
            1 + node.children.reduce(0) { $0 + count($1) }
        }
        self.nodeCount = count(root)
    }

    /// The live view a node describes, or `nil` if it has been deallocated since the walk.
    ///
    /// - Parameter id: The node's identity.
    /// - Returns: The view, while it still exists.
    func view(for id: ObjectIdentifier) -> UIView? {
        views[id]?.view
    }
}
#endif
