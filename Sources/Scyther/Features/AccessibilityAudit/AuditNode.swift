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

/// Whether a node itself marks it as one of Scyther's — before any ancestor is considered.
///
/// The first test is the load-bearing one, and it is deliberately *structural*: ``ScytherPresentedUI``
/// is a marker adopted by ``ScytherHostingController``, the controller every screen Scyther puts
/// on screen is hosted in. Ownership of a whole presented screen is therefore decided by which
/// controller owns the view, not by what the view's class happens to be called.
///
/// That distinction is the defect this rule used to have. Every Scyther screen is SwiftUI, so the
/// view a presented screen actually hangs off is `_UIHostingView<MenuView>` — a private SwiftUI
/// type that names Scyther nowhere — and the name-based rules below never fired for it. The audit
/// consequently walked Scyther's own menu and its own report as if they were the app, and drew
/// error boxes over Scyther's close button. Matching `_UIHostingView` instead would only have
/// swapped one guess about a class name for a worse one, at a private symbol Apple may rename.
/// A view cannot be asked what it is called and be relied on to answer usefully; it can be asked
/// who owns it.
///
/// The three name-based tests are kept because they catch what the marker cannot: Scyther's
/// *non-presented* UI — the overlays it installs straight into the app's key window, which have no
/// view controller of their own. `TopLevelViewsWrapper`/`TopLevelView` name those base classes
/// directly, and the `"Scyther"`-prefix fallback catches anything else Scyther draws without this
/// file having to list every one of them and rot the moment a feature is added.
///
/// - Parameter object: The view, controller or element to test.
/// - Returns: `true` when `object` is itself one of Scyther's own.
@MainActor
private func isScytherOwnedType(_ object: AnyObject) -> Bool {
    object is ScytherPresentedUI
        || object is TopLevelViewsWrapper
        || object is TopLevelView
        || String(describing: type(of: object)).hasPrefix("Scyther")
}

/// The next node up from `object` for the purposes of deciding ownership.
///
/// Three chains are stitched into one, because Scyther's own UI is reached through all three:
///
/// - a synthetic accessibility element sits nowhere in the view hierarchy, so it is followed
///   through its `accessibilityContainer` to whatever real object vends it;
/// - a view is followed through the *responder* chain rather than through `superview`. This is
///   the structural step that makes ownership work: `UIResponder.next` returns a view's owning
///   view controller when the view is that controller's root view, and its superview otherwise.
///   A `superview`-only walk stops at the SwiftUI hosting view and never reaches the
///   ``ScytherPresentedUI`` controller sitting directly above it, which is precisely why a
///   presented Scyther screen used to be audited as if it were the app's;
/// - a view controller is followed the same way, up to whatever presents or contains it.
///
/// The walk stops the moment the chain leaves the view/controller hierarchy — at the window's
/// `UIWindowScene`, and beyond that `UIApplication` and the app's delegate. Those belong to the
/// app being debugged and may be named anything at all, so letting the `"Scyther"`-prefix rule
/// reach them could mark every view in an app whose delegate happens to be called `Scyther…` as
/// Scyther's own. A `UIWindow` *is* a `UIView`, so it is still visited: an overlay Scyther one day
/// installs in a window class of its own would be recognised there.
///
/// - Parameter object: The node whose ancestor is wanted.
/// - Returns: The next node up, or `nil` at the top of the chain.
@MainActor
private func ownershipAncestor(of object: NSObject) -> NSObject? {
    if let container = (object as? UIAccessibilityElement)?.accessibilityContainer as? NSObject {
        return container
    }
    guard let next = (object as? UIResponder)?.next else { return nil }
    return next is UIView || next is UIViewController ? next : nil
}

/// Walks from `start` up through ``ownershipAncestor(of:)`` looking for something of Scyther's.
///
/// A view or element that merely sits *inside* Scyther's UI is just as much Scyther's as the
/// root of that subtree — a label inside the menu is not a finding either — so ownership has to
/// propagate up the containment chain rather than testing only the node in hand.
///
/// - Parameter start: The node to start from; it is tested too, not only its ancestors.
/// - Returns: `true` when `start` or any node above it is Scyther's.
@MainActor
private func isAncestryScytherOwned(startingAt start: NSObject) -> Bool {
    var current: NSObject? = start
    while let node = current {
        if isScytherOwnedType(node) { return true }
        current = ownershipAncestor(of: node)
    }
    return false
}

/// Walks a synthetic element's `accessibilityContainer` chain up to the first real `UIView`, and
/// returns that view's window.
///
/// A `UIAccessibilityElement` has no window of its own — only a `UIView` does — but it is always
/// created with a container, and that container's container, and so on, is the same chain
/// `isScytherOwned` already walks for ownership. Finding the window this way (rather than, say,
/// keeping a reference to the key window at audit time) means the element's *actual* window is
/// used even if a container itself sits inside a nested window.
///
/// - Parameter element: The element to resolve a window for.
/// - Returns: The window, or `nil` when nothing in the chain is a view attached to one.
@MainActor
private func resolveWindow(forContainerChainOf element: NSObject) -> UIWindow? {
    var current: NSObject? = element
    while let node = current {
        if let view = node as? UIView { return view.window }
        current = (node as? UIAccessibilityElement)?.accessibilityContainer as? NSObject
    }
    return nil
}

// MARK: - Accessibility children

/// The children of a real `UIView`, without ever asking UIAccessibility to compute them.
///
/// **Do not "simplify" this into a call to `accessibilityElementCount()` /
/// `accessibilityElement(at:)`.** Those two are declared on `NSObject`, so they *look* like a
/// uniform way to read any container's accessibility children, and that is exactly what hung the
/// app the first time this shipped. For a `UIView` that has not had `accessibilityElements` set,
/// asking either of them makes UIAccessibility compute that view's accessibility subtree on the
/// spot — `-[NSObject(AXPrivCategory) _accessibilityElements]`, which descends the whole subtree
/// below the view. Doing that once per view, at every level of a real hierarchy, is quadratic in
/// the size of the screen, and no node cap can save it: the cost is paid inside this function,
/// before ``AccessibilityAuditor/collect(root:)`` ever gets a chance to count the node.
///
/// Reading the `accessibilityElements` property itself is cheap — it is a stored value that is
/// `nil` until somebody assigns it — so it is safe to ask, and it is the only thing worth asking:
/// an app (or SwiftUI, which sets it on the hosting view that vends its synthetic
/// `AccessibilityNode` elements) that has deliberately replaced its subviews with accessibility
/// elements has *set* it. A view that has not set it has nothing to say that `subviews` does not,
/// so the walk descends the view hierarchy instead and lets each subview answer for itself.
///
/// - Parameter view: The view to read children from.
/// - Returns: The view's `accessibilityElements` when it has been set, its `subviews` otherwise.
@MainActor
private func viewChildren(of view: UIView) -> [AuditNode] {
    if let elements = view.accessibilityElements, !elements.isEmpty {
        return elements.compactMap(auditNode(wrapping:))
    }
    return view.subviews
}

/// The children of a synthetic accessibility element — an `NSObject` that is not a `UIView`.
///
/// This is the one place the older `accessibilityElementCount()`/`accessibilityElement(at:)` pair
/// is still read, and it is safe here for the two reasons it is not safe on a `UIView`: a
/// synthetic element has no `subviews` to fall back to, so refusing to ask would simply lose
/// every child it vends; and an object that implements that pair implements it itself, returning
/// a list it already holds, rather than routing into UIAccessibility's recursive computation of a
/// view subtree. VoiceOver reads containers the same way, preferring `accessibilityElements` and
/// falling back to the pair, so the audit sees what VoiceOver sees.
///
/// - Parameter element: The element to read children from.
/// - Returns: The element's accessibility children, or `[]` when it vends none.
@MainActor
private func syntheticChildren(of element: NSObject) -> [AuditNode] {
    if let elements = element.accessibilityElements, !elements.isEmpty {
        return elements.compactMap(auditNode(wrapping:))
    }
    let count = element.accessibilityElementCount()
    guard count > 0 else { return [] }
    return (0..<count).compactMap { index in
        element.accessibilityElement(at: index).flatMap(auditNode(wrapping:))
    }
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
    /// on being outside the app's hierarchy — it has to recognise Scyther's own views *and the
    /// controllers Scyther presents*, then propagate that down so a label or button inside
    /// Scyther's UI is caught too, not only the container that owns it. The walk goes up the
    /// responder chain rather than up `superview`, which is what lets it reach the owning view
    /// controller — see `ownershipAncestor(of:)`.
    var isScytherOwned: Bool {
        isAncestryScytherOwned(startingAt: self)
    }

    /// Direct read of the dynamic type name, used when a node has no label to identify it by.
    var typeName: String { String(describing: type(of: self)) }

    /// Accessibility children when the view has actually *set* `accessibilityElements`,
    /// `subviews` otherwise — see `viewChildren(of:)` for why a view is never asked to compute
    /// its accessibility children, which is the difference between this screen opening and this
    /// screen hanging the app.
    var children: [AuditNode] { viewChildren(of: self) }
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

    /// `accessibilityFrame` is documented in *screen* coordinates, not window coordinates — the
    /// two only coincide when the window happens to fill the screen from its origin, which is not
    /// true in Split View, Slide Over, Stage Manager, or any other non-fullscreen scene. Returning
    /// it unconverted would misplace the overlay box and, worse, feed the contrast sampler a crop
    /// rectangle in the wrong space entirely — one that can land outside the window's own bounds
    /// and make `WindowContrastSampler.samples(in:)` return `[]`, silently dropping a real finding
    /// rather than reporting it in the wrong place. So this resolves the element's actual window
    /// through its container chain and converts into that window's own coordinate space. When no
    /// window can be resolved (a container never attached to one, as in some of the tests below),
    /// the raw frame is the least-wrong fallback: it is still a valid frame in *some* space, and
    /// silently returning `.zero` would instead make the element invisible to every check.
    var frameInWindow: CGRect {
        guard let window = resolveWindow(forContainerChainOf: element) else {
            return element.accessibilityFrame
        }
        return window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace)
    }

    /// A synthetic element has no `isHidden`/`alpha` of its own to read: a container only lists
    /// it in `accessibilityElements`, or hands it back from `accessibilityElement(at:)`, while it
    /// wants VoiceOver to find it, so being reachable at all is the element's own signal that it
    /// is meant to be visible.
    var isVisible: Bool { true }

    /// Exactly the same rule as `UIView.isScytherOwned`, and deliberately the same walk: a
    /// synthetic element has no superview of its own, so `ownershipAncestor(of:)` starts by
    /// following `accessibilityContainer` and then — once that chain reaches a real view —
    /// continues up the responder chain to whichever controller owns it. Sharing the walk is what
    /// stops a SwiftUI `AccessibilityNode` vended by Scyther's own menu from being audited while
    /// the `UIView` beside it is not.
    var isScytherOwned: Bool {
        isAncestryScytherOwned(startingAt: element)
    }

    /// Direct read of the wrapped element's dynamic type name.
    var typeName: String { String(describing: type(of: element)) }

    /// Accessibility children when the element declares any — `UIAccessibilityElement` rarely
    /// does, but nothing stops a custom `NSObject` from doing so — an empty list otherwise, since
    /// a synthetic element has no subviews to fall back to. Unlike a `UIView`, a synthetic element
    /// *is* asked for `accessibilityElementCount()`; see `syntheticChildren(of:)` for why that is
    /// safe here and ruinous there.
    var children: [AuditNode] { syntheticChildren(of: element) }
}
