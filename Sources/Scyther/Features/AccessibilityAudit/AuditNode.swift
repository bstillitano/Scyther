import UIKit

/// One node of the tree the audit walks.
///
/// The audit walks the *accessibility* tree, not the view tree: a SwiftUI `Text` is not a
/// `UILabel`, and a walk over `subviews` finds a drawing layer with no label, no traits and
/// nothing to check. This protocol is what the checks see, so every one of them is testable
/// against a handful of values rather than against a running app.
@MainActor
protocol AuditNode {
    /// Whether this node is itself an accessibility element — a leaf, in VoiceOver's terms.
    var isAccessibilityElementNode: Bool { get }

    /// The label VoiceOver would read, if any.
    var accessibilityLabelText: String? { get }

    /// What VoiceOver is told this element is.
    var traits: UIAccessibilityTraits { get }

    /// The node's frame in window coordinates, which is where the overlay draws.
    var frameInWindow: CGRect { get }

    /// Whether the node can be seen: on screen, not hidden, not fully transparent.
    var isVisible: Bool { get }

    /// Whether the node belongs to Scyther rather than to the app under audit.
    var isScytherOwned: Bool { get }

    /// The node's type, for naming an element that has no label.
    var typeName: String { get }

    /// The nodes below this one: accessibility children where there are any, subviews otherwise.
    var children: [AuditNode] { get }
}

// MARK: - Scyther ownership

/// Whether a node's own type marks it as one of Scyther's — before any ancestor is considered.
///
/// Both adapters below need this test, and both need to repeat it up an ancestor chain (a
/// `UIView`'s superviews, or a synthetic element's `accessibilityContainer`), so it is pulled
/// out rather than written twice. `TopLevelViewsWrapper`/`TopLevelView` catch Scyther's overlay
/// classes directly; the `"Scyther"`-prefix fallback catches everything else Scyther draws
/// (its menu, its inspectors) without this file needing to name every one of them and rot the
/// moment a new feature is added.
///
/// - Parameter object: The view or element to test.
/// - Returns: `true` when `object` is itself one of Scyther's own types.
@MainActor
private func isScytherOwnedType(_ object: AnyObject) -> Bool {
    object is TopLevelViewsWrapper
        || object is TopLevelView
        || String(describing: type(of: object)).hasPrefix("Scyther")
}

/// Walks from `start` up through `ancestor` looking for a Scyther type.
///
/// A view or element that merely sits *inside* Scyther's UI is just as much Scyther's as the
/// root of that subtree — a label inside the menu is not a finding either — so ownership has to
/// propagate up the containment chain rather than testing only the node in hand.
///
/// - Parameters:
///   - start: The node to start from; it is tested too, not only its ancestors.
///   - ancestor: Returns the next node up, or `nil` at the top.
/// - Returns: `true` when `start` or any node reached through `ancestor` is Scyther's.
@MainActor
private func isAncestryScytherOwned(startingAt start: NSObject, ancestor: (NSObject) -> NSObject?) -> Bool {
    var current: NSObject? = start
    while let node = current {
        if isScytherOwnedType(node) { return true }
        current = ancestor(node)
    }
    return false
}

// MARK: - Accessibility children

/// Turns an `NSObject` accessibility container into `AuditNode` children.
///
/// VoiceOver itself prefers `accessibilityElements` over the view hierarchy when a container
/// sets it, and falls back to the older `accessibilityElementCount()`/`accessibilityElement(at:)`
/// pair when a container implements those instead; both are declared on plain `NSObject`, not
/// just `UIView`, so this reads them without caring whether `object` is a view or a synthetic
/// element. The audit has to walk whichever one a container actually uses, or it finds subviews
/// an app deliberately replaced with synthetic elements — the whole reason
/// ``testAccessibilityChildrenWinOverSubviews`` exists.
///
/// - Parameters:
///   - object: The container to read children from.
///   - fallback: What to use when `object` declares neither — a view's `subviews`, or nothing.
/// - Returns: The container's accessibility children, or `fallback()`.
@MainActor
private func accessibilityChildren(of object: NSObject, fallback: @autoclosure () -> [AuditNode]) -> [AuditNode] {
    if let elements = object.accessibilityElements, !elements.isEmpty {
        return elements.compactMap(auditNode(wrapping:))
    }
    let count = object.accessibilityElementCount()
    if count > 0 {
        return (0..<count).compactMap { index in
            object.accessibilityElement(at: index).flatMap(auditNode(wrapping:))
        }
    }
    return fallback()
}

/// Wraps one entry from `accessibilityElements`/`accessibilityElement(at:)` as an `AuditNode`.
///
/// An entry is most often a `UIView`, which already conforms to `AuditNode` and should be kept
/// as itself so its own subview/accessibility-children logic still applies further down; when it
/// is instead a synthetic `NSObject` such as `UIAccessibilityElement`, it is wrapped in
/// ``AccessibilityElementNode``.
///
/// - Parameter any: One element from a container's accessibility children.
/// - Returns: The wrapped node, or `nil` when `any` is neither a view nor an `NSObject`.
@MainActor
private func auditNode(wrapping any: Any) -> AuditNode? {
    if let node = any as? AuditNode { return node }
    if let object = any as? NSObject { return AccessibilityElementNode(element: object) }
    return nil
}

// MARK: - UIView

/// Adapts the real view hierarchy to ``AuditNode``.
///
/// This is the bridge between UIKit's actual accessibility APIs and the pure model the rest of
/// the audit is written against — every property here is a direct, untransformed read of the
/// UIKit property the doc comment names, so there is nowhere for the adapter itself to disagree
/// with what VoiceOver sees.
@MainActor
extension UIView: AuditNode {
    /// Direct read of `isAccessibilityElement` — whether VoiceOver treats this view as a leaf.
    var isAccessibilityElementNode: Bool { isAccessibilityElement }

    /// Direct read of `accessibilityLabel`.
    var accessibilityLabelText: String? { accessibilityLabel }

    /// Direct read of `accessibilityTraits`.
    var traits: UIAccessibilityTraits { accessibilityTraits }

    /// `frame` is in the superview's coordinate space, but the overlay draws in window
    /// coordinates and the contrast sampler reads window-space pixels, so this converts through
    /// the superview chain rather than exposing `frame` itself. A view with no superview (not
    /// yet installed, or the window itself) has nothing to convert through, so its own frame is
    /// already the answer.
    var frameInWindow: CGRect { superview?.convert(frame, to: nil) ?? frame }

    /// A view that is hidden, or effectively invisible at near-zero alpha, shows nothing for
    /// VoiceOver or a sighted user to perceive, so it is excluded the same way a `0`-sized frame
    /// is: the audit should not report contrast or labelling problems for pixels nobody sees.
    var isVisible: Bool { !isHidden && alpha > 0.01 }

    /// Scyther's overlays live inside the app's own key window, so recognising them can't rely
    /// on being outside the app's hierarchy — it has to recognise Scyther's own view classes and
    /// then propagate that up so a label or button *inside* Scyther's UI is caught too, not only
    /// the container that owns it.
    var isScytherOwned: Bool {
        isAncestryScytherOwned(startingAt: self) { ($0 as? UIView)?.superview }
    }

    /// Direct read of the dynamic type name, used when a node has no label to identify it by.
    var typeName: String { String(describing: type(of: self)) }

    /// Accessibility children when the view declares any, `subviews` otherwise.
    var children: [AuditNode] { accessibilityChildren(of: self, fallback: subviews) }
}

// MARK: - AccessibilityElementNode

/// Adapts a synthetic accessibility element — most often a `UIAccessibilityElement` — to
/// ``AuditNode``.
///
/// VoiceOver does not distinguish a `UIView` from a `UIAccessibilityElement` placed in a
/// container's `accessibilityElements`: both are just elements it can land on. This wraps the
/// `NSObject` case so the audit walks the two identically, using the same `isAccessibilityElement`
/// / `accessibilityLabel` / `accessibilityTraits` / `accessibilityFrame` properties UIKit already
/// declares on `NSObject` for exactly this purpose.
@MainActor
struct AccessibilityElementNode: AuditNode {
    /// The wrapped accessibility element.
    private let element: NSObject

    /// Wraps an accessibility element.
    ///
    /// - Parameter element: The `NSObject` — typically a `UIAccessibilityElement` — to adapt.
    init(element: NSObject) {
        self.element = element
    }

    /// Direct read of `isAccessibilityElement`.
    var isAccessibilityElementNode: Bool { element.isAccessibilityElement }

    /// Direct read of `accessibilityLabel`.
    var accessibilityLabelText: String? { element.accessibilityLabel }

    /// Direct read of `accessibilityTraits`.
    var traits: UIAccessibilityTraits { element.accessibilityTraits }

    /// Unlike a view's `frame`, `accessibilityFrame` is already expressed in screen coordinates —
    /// the same space `UIView.frameInWindow` converts *into* — so there is nothing to convert
    /// here; converting it again would be the bug, not the fix.
    var frameInWindow: CGRect { element.accessibilityFrame }

    /// A synthetic element has no `isHidden`/`alpha` of its own to read: a container only lists
    /// it in `accessibilityElements`, or hands it back from `accessibilityElement(at:)`, while it
    /// wants VoiceOver to find it, so being reachable at all is the element's own signal that it
    /// is meant to be visible.
    var isVisible: Bool { true }

    /// Same rule as `UIView.isScytherOwned`, walked through `accessibilityContainer` instead of
    /// `superview` since a synthetic element usually has no superview of its own.
    /// `accessibilityContainer` is declared by `UIAccessibilityElement` itself rather than by
    /// `NSObject` in general — unlike `isAccessibilityElement`/`accessibilityLabel`/etc, which
    /// every accessibility element has — so the cast narrows to that before reading it.
    var isScytherOwned: Bool {
        isAncestryScytherOwned(startingAt: element) { object in
            (object as? UIAccessibilityElement)?.accessibilityContainer as? NSObject
        }
    }

    /// Direct read of the wrapped element's dynamic type name.
    var typeName: String { String(describing: type(of: element)) }

    /// Accessibility children when the element declares any — `UIAccessibilityElement` rarely
    /// does, but nothing stops a custom `NSObject` from doing so — an empty list otherwise, since
    /// a synthetic element has no subviews to fall back to.
    var children: [AuditNode] { accessibilityChildren(of: element, fallback: []) }
}
