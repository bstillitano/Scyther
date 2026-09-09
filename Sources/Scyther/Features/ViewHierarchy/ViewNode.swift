//
//  ViewNode.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// One view in a hierarchy snapshot.
///
/// A value type that deliberately holds **no reference to the `UIView` it describes**. A tree
/// that strongly held views would keep an entire screen alive for as long as the inspector's
/// page was open; the one operation that needs the real view — the thumbnail — goes through
/// ``ViewHierarchySnapshot``'s weak side table instead.
///
/// `id` is the described view's `ObjectIdentifier`, which is `Sendable` and is exactly the
/// question the side table asks. It is an identity token, not a reference: it says nothing about
/// whether the view is still alive.
struct ViewNode: Identifiable, Equatable, Sendable {
    /// The identity of the view this node describes.
    let id: ObjectIdentifier

    /// The view's class name, as `String(describing: type(of: view))`.
    let className: String

    /// The view's frame converted into the window's coordinate space.
    let frameInWindow: CGRect

    /// How many ancestors sit between this node and the root. The root is `0`.
    let depth: Int

    /// Text the view carries itself — a `UILabel`'s `text`, a `UIButton`'s current title —
    /// or `nil`. Never read from an accessibility property.
    let text: String?

    /// Whether the view is invisible: `isHidden`, or an effective alpha at or below `0.01`
    /// anywhere in its ancestry.
    let isHidden: Bool

    /// Whether the view has a zero width or a zero height.
    let isZeroSize: Bool

    /// Whether the view's window-space frame does not intersect the window's bounds.
    let isOffScreen: Bool

    /// This node's children, in subview order.
    let children: [ViewNode]

    /// The view's size, in points.
    var size: CGSize { frameInWindow.size }

    // MARK: - Indentation

    /// The deepest level the tree indents to.
    ///
    /// Beyond this, indentation stops growing. A hierarchy forty levels deep would otherwise
    /// push a class name off the right of a phone, and the row's own label is worth more than
    /// a faithful indent. The real depth is untouched, and search's ancestor path carries the
    /// full chain for anyone who needs it.
    static let maximumIndentationDepth: Int = 8

    /// How far to indent a row at `depth`, capped at ``maximumIndentationDepth``.
    ///
    /// - Parameter depth: The node's real depth.
    /// - Returns: The indentation level to draw, never greater than the cap.
    static func indentationLevel(forDepth depth: Int) -> Int {
        min(max(depth, 0), maximumIndentationDepth)
    }
}
#endif
