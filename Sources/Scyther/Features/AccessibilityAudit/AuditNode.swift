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
        || isScytherNamedClass(type(of: object))
}

/// The answer `isScytherNamedClass(_:)` has already worked out for a class, keyed by that class.
///
/// Sound because the question is a pure function of the class — a type's name cannot change at
/// runtime — and bounded because a process contains a fixed set of classes, a few hundred of which
/// the audit will ever meet.
@MainActor
private var scytherNamedClasses: [ObjectIdentifier: Bool] = [:]

/// Whether a class's *name* begins with `Scyther`, worked out once per class.
///
/// The name test is the last clause of ``isScytherOwnedType(_:)`` and the only expensive one: for
/// an app's own views the three `is` tests all fail, so `String(describing:)` runs every time, and
/// each run is a Swift runtime metatype demangle plus a `String` allocation. It is asked once per
/// ancestor per node — a screen at the node cap with an average chain depth of 25 is roughly
/// 125,000 demangles inside a 0.25s budget, which made a string comparison that answers "no" the
/// dominant cost of the whole walk and was very likely why real screens reported themselves too
/// big to audit.
///
/// Memoising by class keeps the rule *exactly* as it was — same string, same prefix — while paying
/// for it once per class rather than once per node. `NSStringFromClass` was the other candidate and
/// is worse: for a Swift class it returns the mangled `_TtC7Scyther…` form, so the prefix rule this
/// file documents would have had to be rewritten around a name mangling Apple does not guarantee.
///
/// - Parameter type: The class to test.
/// - Returns: `true` when its name begins with `Scyther`.
@MainActor
private func isScytherNamedClass(_ type: AnyObject.Type) -> Bool {
    let key = ObjectIdentifier(type)
    if let known = scytherNamedClasses[key] { return known }
    let named = String(describing: type).hasPrefix("Scyther")
    scytherNamedClasses[key] = named
    return named
}

/// How far the two ancestor walks in this file may climb before giving up.
///
/// Both of them follow `accessibilityContainer`, which is an app-settable weak reference
/// (`UIAccessibilityElement.h`), so `element.accessibilityContainer = element` — or any longer
/// cycle — is a hierarchy an app can build by accident and neither walk had anything to stop it.
/// That is not a slow audit but a hung main thread: the loop runs *inside a single node's property
/// read*, before ``AccessibilityAuditor/collect(root:)`` reaches its next deadline check, so none
/// of the walk's three caps can reach it. A counter is enough, it matches
/// ``AccessibilityAuditor/maximumDepth`` — a containment chain deeper than the tree depth the walk
/// itself refuses to descend is pathological either way — and it costs one integer compare per
/// link rather than the allocation a set of `ObjectIdentifier`s would.
private let maximumAncestryDepth = 100

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
/// The climb is bounded by `maximumAncestryDepth` because one link of it is an app-settable
/// `accessibilityContainer` that can point back down at itself; see that constant for why an
/// unbounded loop here is a hang no cap in the walk can interrupt. Giving up early answers
/// `false` — "not Scyther's" — which is the safe direction: at worst a cycle inside Scyther's own
/// UI gets audited, where the honest failure is a spurious finding rather than a frozen app.
///
/// - Parameter start: The node to start from; it is tested too, not only its ancestors.
/// - Returns: `true` when `start` or any node above it is Scyther's.
@MainActor
private func isAncestryScytherOwned(startingAt start: NSObject) -> Bool {
    var current: NSObject? = start
    var steps = 0
    while let node = current, steps < maximumAncestryDepth {
        if isScytherOwnedType(node) { return true }
        current = ownershipAncestor(of: node)
        steps += 1
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
/// Bounded by `maximumAncestryDepth` for the same reason as `isAncestryScytherOwned(startingAt:)`:
/// this chain is nothing but `accessibilityContainer` links, so it is the more exposed of the two.
/// Giving up returns `nil`, which the caller already handles as "no window resolved".
///
/// - Parameter element: The element to resolve a window for.
/// - Returns: The window, or `nil` when nothing in the chain is a view attached to one.
@MainActor
private func resolveWindow(forContainerChainOf element: NSObject) -> UIWindow? {
    resolveContainerView(forContainerChainOf: element)?.window
}

/// Walks a synthetic element's `accessibilityContainer` chain up to the first real `UIView`.
///
/// The view, not its window, because two questions need it: which window the element's frame is
/// expressed against, and what the element is clipped by — a synthetic element has no geometry of
/// its own beyond `accessibilityFrame`, so the view that vends it is the only thing that can say
/// whether it is on screen at all.
///
/// Bounded by `maximumAncestryDepth`; see `isAncestryScytherOwned(startingAt:)` for why.
///
/// - Parameter element: The element to resolve a container view for.
/// - Returns: The first view in the chain, or `nil` when nothing in it is a view.
@MainActor
private func resolveContainerView(forContainerChainOf element: NSObject) -> UIView? {
    var current: NSObject? = element
    var steps = 0
    while let node = current, steps < maximumAncestryDepth {
        if let view = node as? UIView { return view }
        current = (node as? UIAccessibilityElement)?.accessibilityContainer as? NSObject
        steps += 1
    }
    return nil
}

// MARK: - Visibility

/// The part of the window a view's content can actually reach the screen through.
///
/// Everything the walk sees is laid out and unhidden; that is not the same as being on screen. A
/// `UITableView` keeps roughly a screen's worth of cells alive above and below the viewport, a
/// paged carousel keeps its neighbours laid out to the left and right, and a `NavigationStack`
/// parks the outgoing screen off canvas — all real views with real, non-empty window frames, none
/// of them visible, all of them audited and boxed until now. `convert` resolves their frames
/// correctly to somewhere the developer cannot look.
///
/// So the window's own bounds and every `clipsToBounds` ancestor's bounds are intersected into one
/// region, which is the same arithmetic the compositor does. The window itself is skipped in the
/// loop because its bounds are the starting region already.
///
/// - Parameters:
///   - view: The view to compute the region for.
///   - space: The coordinate space to express the region in — see
///     ``ScytherPresentation/untransformedMeasurementSpace(for:)``; frames and clips must be
///     compared in the *same* space or the comparison is meaningless.
///   - window: The window `view` is installed in.
///   - includingOwnClip: Whether `view`'s own clipping counts. It does for a synthetic element
///     vended by `view`, which is drawn inside it; it does not for `view` itself, which is not
///     clipped by its own bounds.
/// - Returns: The visible region, or a null rect when nothing of it is left.
@MainActor
private func clippedRegion(for view: UIView,
                           in space: UIView,
                           window: UIWindow,
                           includingOwnClip: Bool = false) -> CGRect {
    var region = space.convert(window.bounds, from: window)
    var current: UIView? = includingOwnClip ? view : view.superview
    var steps = 0
    while let ancestor = current, steps < maximumAncestryDepth {
        if ancestor !== window, ancestor.clipsToBounds {
            region = region.intersection(space.convert(ancestor.bounds, from: ancestor))
            if region.isNull || region.isEmpty { return .null }
        }
        current = ancestor.superview
        steps += 1
    }
    return region
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
/// The one case that exception loses is a view with **no subviews at all** — Apple's documented
/// custom-container pattern (`UIAccessibilityContainer.h`): a chart, seat map, calendar grid or
/// keypad that draws its content in `draw(_:)` and vends one `UIAccessibilityElement` per datum
/// from `accessibilityElement(at:)` without ever setting `accessibilityElements`. Reading only
/// `subviews` there collects nothing and reports the screen clean, for precisely the kind of
/// hand-rolled view where accessibility defects actually live. Such a view is asked, and only such
/// a view: the cost the exception exists to avoid is UIAccessibility descending the view's
/// *subtree*, and a view with no subviews has no subtree to descend.
///
/// "Set" means set, including set to `[]`. Assigning an empty array is the documented way an app
/// says "this container vends nothing, ignore what is inside me", and testing `!isEmpty` turned
/// that instruction into a fall-through to `subviews` — the walk then reported a
/// `.missingLabel` error for every decorative image inside a banner the app had deliberately
/// hidden. `nil` and `[]` are different answers and are now treated as different answers.
///
/// `accessibilityElementsHidden` says the same thing about a subtree the app kept as real views:
/// the card that sets `isAccessibilityElement = true` on itself and hides its contents so
/// VoiceOver reads one summary instead of six fragments. Those six are not reachable, so they are
/// not walked. The view carrying the flag is still checked itself — the flag hides what is
/// *contained within* an element, not the element — which is exactly the card's own case.
///
/// - Parameter view: The view to read children from.
/// - Returns: Nothing when the view hides its contents; its `accessibilityElements` when it has
///   set them; the elements it declares when it has no subviews; its `subviews` otherwise.
@MainActor
private func viewChildren(of view: UIView) -> [AuditNode] {
    if view.accessibilityElementsHidden { return [] }
    if let elements = view.accessibilityElements {
        return auditNodes(from: elements)
    }
    let subviews = view.subviews
    guard subviews.isEmpty else { return honouringModality(subviews) }
    return declaredElements(of: view)
}

/// The children a view vends through `accessibilityElementCount()`/`accessibilityElement(at:)`.
///
/// Only ever called for a view with no subviews — see `viewChildren(of:)` for why that condition
/// is what makes asking safe. The count is sanity-checked rather than trusted: `NSObject`'s default
/// implementation answers `NSNotFound` when it has nothing to say, and iterating that would be a
/// hang dressed up as a loop, so anything absurd is treated as "vends nothing".
///
/// - Parameter view: The leaf view to ask.
/// - Returns: The elements it vends, or `[]` when it vends none.
@MainActor
private func declaredElements(of view: UIView) -> [AuditNode] {
    let count = view.accessibilityElementCount()
    guard count > 0, count <= maximumDeclaredElements else { return [] }
    let elements = (0..<count).compactMap { view.accessibilityElement(at: $0) }
    return auditNodes(from: elements)
}

/// The most elements a container is believed when it says it vends.
///
/// `NSNotFound` is the value that matters — `accessibilityElementCount()`'s documented "nothing to
/// report" answer, and `Int.max` to a `for` loop. The number itself is chosen to be far larger than
/// any real container (``AccessibilityAuditor/maximumNodes`` would stop the walk long before) and
/// far smaller than an accident.
private let maximumDeclaredElements = 100_000

/// Wraps a container's accessibility children, honouring any modal among them.
///
/// - Parameter objects: The raw entries from `accessibilityElements` or `accessibilityElement(at:)`.
/// - Returns: The wrapped nodes, in the order VoiceOver would reach them.
@MainActor
private func auditNodes(from objects: [Any]) -> [AuditNode] {
    honouringModality(objects.compactMap { $0 as? NSObject }).compactMap(auditNode(wrapping:))
}

/// Applies `accessibilityViewIsModal` to one container's children.
///
/// A node that sets it tells VoiceOver to ignore every *sibling* subtree, which is how an in-app
/// dialog, bottom sheet or custom alert makes the screen behind it unreachable. The walk did not
/// honour it, so every control underneath such a dialog was audited and boxed — findings about
/// elements no assistive-technology user can land on, drawn behind the thing covering them.
///
/// Siblings, and only siblings: an ancestor's siblings stay reachable, which is what UIKit
/// documents and what makes this a per-container filter rather than a global one. The *last* modal
/// wins when there are several, matching the way the topmost sibling is the one drawn over the
/// others.
///
/// A modal that cannot be seen does not suppress anything. Apps routinely keep a dismissed dialog
/// around hidden or at zero alpha, and honouring the flag on one of those would silently empty the
/// audit for the whole screen — the worst possible failure for a tool whose output is a list of
/// what is wrong, since an empty list reads as "nothing is". A non-view element has no visibility
/// of its own to read and is taken at its word, exactly as ``AccessibilityElementNode/isVisible``
/// takes it.
///
/// - Parameter children: One container's children, in order.
/// - Returns: Just the modal child when there is one, all of them otherwise.
@MainActor
private func honouringModality<Element: NSObject>(_ children: [Element]) -> [Element] {
    let modal = children.last { child in
        guard child.accessibilityViewIsModal else { return false }
        guard let view = child as? UIView else { return true }
        return !view.isHidden && view.alpha > 0.01
    }
    guard let modal else { return children }
    return [modal]
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
/// `accessibilityElementsHidden` and `accessibilityViewIsModal` are read here exactly as they are
/// for a view: both are declared on `NSObject`'s `UIAccessibility` category, so a synthetic
/// container can set them and VoiceOver honours them when it does.
///
/// - Parameter element: The element to read children from.
/// - Returns: The element's accessibility children, or `[]` when it vends none.
@MainActor
private func syntheticChildren(of element: NSObject) -> [AuditNode] {
    if element.accessibilityElementsHidden { return [] }
    if let elements = element.accessibilityElements {
        return auditNodes(from: elements)
    }
    let count = element.accessibilityElementCount()
    guard count > 0, count <= maximumDeclaredElements else { return [] }
    let children = (0..<count).compactMap { element.accessibilityElement(at: $0) }
    return auditNodes(from: children)
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

    /// The view's geometry, in the space the audit measures in.
    ///
    /// Converted rather than exposed raw because the overlay draws in window coordinates and the
    /// contrast sampler reads window-space pixels. Two things changed here, and both were wrong
    /// answers rather than untidiness.
    ///
    /// The conversion starts from `bounds`, not `frame`: Apple documents `frame` as undefined when
    /// `transform` is not the identity, and `convert(bounds, to:)` is defined in every case and
    /// identical to the old form whenever no transform is involved. A view with no superview (not
    /// yet installed, or the window itself) has nothing to convert through, so its `bounds` — the
    /// window's own origin in its own space — is already the answer.
    ///
    /// And it measures in ``ScytherPresentation/untransformedMeasurementSpace(for:)`` when there
    /// is one. `convert(_:to: nil)` composes *every* transform on the way up, and when the audit
    /// runs from Scyther's own report — which is the only way a developer reads touch-target
    /// numbers — one of those transforms is Scyther's. UIKit builds the card behind a page sheet
    /// by scaling and translating the presenting view controller's view, which is the app under
    /// audit, so a compliant 44 × 44pt control measured through the sheet reads about
    /// 40.5 × 40.5pt and was reported as an error that does not exist in the app. Measuring in the
    /// transformed ancestor's own coordinate space removes that transform and only that one: the
    /// app's own transforms sit below it and still apply, because a control an app really does
    /// draw at half scale really is half the size.
    var frameInWindow: CGRect {
        guard superview != nil else { return bounds }
        guard let space = ScytherPresentation.untransformedMeasurementSpace(for: self) else {
            return convert(bounds, to: nil)
        }
        return convert(bounds, to: space)
    }

    /// Whether any of this view can actually be seen.
    ///
    /// Hidden and near-zero alpha are the easy half: they show nothing for VoiceOver or a sighted
    /// user to perceive, so they are excluded the same way a `0`-sized frame is. The other half is
    /// being on screen at all — see `clippedRegion(for:in:window:includingOwnClip:)` for the
    /// recycled cells, parked screens and clipped carousels this used to report. A node with
    /// nothing left is skipped along with everything below it, which is sound: a subview cannot be
    /// visible through a container that is not.
    ///
    /// A view with no window is not clipped by anything and cannot be off the edge of anything, so
    /// it stays visible. That is the not-yet-installed case, and every unit test's case.
    var isVisible: Bool {
        guard !isHidden, alpha > 0.01 else { return false }
        guard let window else { return true }
        let space = ScytherPresentation.untransformedMeasurementSpace(for: self) ?? window
        return clippedRegion(for: self, in: space, window: window).intersects(frameInWindow)
    }

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
    /// Once in the window's space it is put through the same transform correction as a view's —
    /// see ``UIView/frameInWindow`` — because `accessibilityFrame` is where the element is
    /// *rendered*, and while Scyther's sheet is up that is through Scyther's card transform.
    var frameInWindow: CGRect {
        guard let container = resolveContainerView(forContainerChainOf: element),
              let window = container.window else {
            return element.accessibilityFrame
        }
        let inWindow = window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace)
        guard let space = ScytherPresentation.untransformedMeasurementSpace(for: container) else {
            return inWindow
        }
        return space.convert(inWindow, from: window)
    }

    /// A synthetic element has no `isHidden`/`alpha` of its own to read: a container only lists
    /// it in `accessibilityElements`, or hands it back from `accessibilityElement(at:)`, while it
    /// wants VoiceOver to find it, so being reachable at all is the element's own signal that it
    /// is meant to be visible.
    ///
    /// Where it is drawn is a different question, and one it can answer: an element vended by a
    /// row that has scrolled out of a `UITableView`, or by a page parked off to the side of a
    /// carousel, is as unreachable as the view that vends it. So the element's frame is tested
    /// against the region its container view can be seen through — including that view's own
    /// clipping, since the element is drawn *inside* it rather than beside it. An element whose
    /// container resolves to no window keeps the old answer: there is nothing to be off the edge
    /// of, and the tests build exactly that shape.
    var isVisible: Bool {
        guard let container = resolveContainerView(forContainerChainOf: element),
              let window = container.window else {
            return true
        }
        let space = ScytherPresentation.untransformedMeasurementSpace(for: container) ?? window
        let region = clippedRegion(for: container, in: space, window: window, includingOwnClip: true)
        return region.intersects(frameInWindow)
    }

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
