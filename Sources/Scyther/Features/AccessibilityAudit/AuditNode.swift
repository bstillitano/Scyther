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

    /// Where the node is, or `nil` when nothing of it can be seen.
    ///
    /// One question rather than the two — ``frameInWindow`` and ``isVisible`` — that the walk used
    /// to ask, because on a real node those two are not independent: deciding visibility needs the
    /// frame, and both need the coordinate space Scyther's own presentation may have transformed.
    /// Asked separately, every node resolved that space twice and converted its own bounds twice,
    /// for two answers computed from the same inputs one line apart. At the 5,000-node cap that is
    /// two redundant ancestor climbs per node inside a budget measured in milliseconds.
    ///
    /// The default implementation composes the two originals, so a test double — or any conformer
    /// with no geometry of its own to share — needs to say nothing. ``UIView`` and
    /// ``AccessibilityElementNode`` override it to resolve the space once and hand it to
    /// everything that needs it.
    var frameInWindowIfVisible: CGRect? { get }

    /// The object this node stands for, so the walk can hand it to the node's children as a
    /// boundary for their own ownership climb. `nil` for a node that is not backed by one.
    ///
    /// An identity token rather than the object itself, and deliberately so. The boundary is
    /// only ever compared for identity — `isAncestryScytherOwned` does one `==` against it and
    /// nothing else — so carrying the object bought nothing and cost Sendability: a non-`Sendable`
    /// `AnyObject?` threaded through a recursive walk is a value crossing isolation, which Swift
    /// 6.2 diagnoses as a data race. `ObjectIdentifier` is `Sendable` and is exactly the question
    /// being asked.
    ///
    /// - SeeAlso: ``isScytherOwned(below:)``.
    var ownershipIdentity: ObjectIdentifier? { get }

    /// Whether this node, or anything above it, belongs to Scyther — given that `boundary` and
    /// everything above `boundary` is already known not to.
    ///
    /// Scyther-ownership is inherited: the walk never descends into a node it has decided is
    /// Scyther's, so by the time a child is tested its parent chain has already been cleared all
    /// the way to the top. Climbing that chain again for every child made the question quadratic
    /// in the depth of the screen — and it is the one question whose answer is `false` for every
    /// node in the app being debugged.
    ///
    /// `boundary` is only ever an early exit: a chain that never reaches it — a synthetic element
    /// whose `accessibilityContainer` points somewhere else entirely — is climbed in full exactly
    /// as before, so nothing of Scyther's can be missed by stopping early at something that was
    /// checked already.
    ///
    /// - Parameter boundary: A node already known to be clean, or `nil` to climb the whole chain.
    /// - Returns: `true` when this node or an ancestor below `boundary` is Scyther's.
    func isScytherOwned(below boundary: ObjectIdentifier?) -> Bool
}

extension AuditNode {
    /// Composes ``frameInWindow`` and ``isVisible``, which is the honest answer for a node that
    /// has no shared work between them to save.
    var frameInWindowIfVisible: CGRect? {
        let frame = frameInWindow
        guard !frame.isEmpty, isVisible else { return nil }
        return frame
    }

    /// Nothing to hand a child, which is the right answer for a node with no object behind it.
    var ownershipIdentity: ObjectIdentifier? { nil }

    /// Ignores the boundary and answers the whole question, which is what a node that cannot
    /// climb an ancestor chain has to do anyway.
    ///
    /// - Parameter boundary: Ignored.
    /// - Returns: ``isScytherOwned``.
    func isScytherOwned(below boundary: ObjectIdentifier?) -> Bool { isScytherOwned }
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
/// The climb also stops the moment it reaches `boundary`, a node the caller has already cleared.
/// The walk descends from parent to child and never descends into anything of Scyther's, so a
/// child's parent — and everything above it — has been tested before the child is reached; the
/// only links that still need testing are the ones between the two. Re-climbing the whole chain
/// per node made this quadratic in the depth of the screen for an answer that is `false`
/// throughout an app. A chain that never reaches `boundary` is climbed in full, so the shortcut
/// can only ever skip links a previous climb has already looked at.
///
/// - Parameters:
///   - start: The node to start from; it is tested too, not only its ancestors.
///   - boundary: A node already known not to be Scyther's, or `nil` to climb the whole chain.
/// - Returns: `true` when `start` or any node above it and below `boundary` is Scyther's.
@MainActor
private func isAncestryScytherOwned(startingAt start: NSObject, stoppingAt boundary: ObjectIdentifier? = nil) -> Bool {
    var current: NSObject? = start
    var steps = 0
    while let node = current, steps < maximumAncestryDepth {
        if let boundary, ObjectIdentifier(node) == boundary { return false }
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

/// How many views one occlusion query may look at before it gives up.
///
/// The query runs per node inside a 0.25s budget and its worst case is quadratic — for each node it
/// looks at the siblings drawn after every ancestor — so it is bounded rather than trusted. Giving
/// up answers "not occluded", which keeps the node: the safe direction, because an unwanted finding
/// is a nuisance and a silently dropped element is a screen certified clean that is not.
private let maximumOcclusionCandidates = 200

/// How deep an occlusion query descends into a covering view looking for its opaque material.
///
/// A bar does not paint itself: `UINavigationBar` draws through a `_UIBarBackground` holding a
/// `UIVisualEffectView`, and SwiftUI nests its materials just as deep. Four or five levels reaches
/// every real one; a limit stops a covering view with a large subtree from being walked in full.
private let maximumOcclusionDepth = 6

/// How many subviews are considered when asking whether a non-clipping container still has content
/// on screen.
///
/// Bounded because it is asked of every container the region test rejects, which on a long list is
/// every recycled cell. A container with more subviews than this that keeps its visible content
/// beyond the cut is pruned, exactly as it was before.
private let maximumEscapeCandidates = 64

/// Whether something opaque is drawn on top of `frame`, hiding it from the developer and from the
/// contrast sampler alike.
///
/// ``clippedRegion(for:in:window:includingOwnClip:)`` handles clipping and only clipping. It has no
/// notion of a *sibling* drawn over the node, and that is a real false positive measured on device:
/// a SwiftUI `List` fills the window and scrolls its content under the navigation bar, so a caption
/// behind the bar is inside the scroll view's bounds, inside the window, and reported at 1.04:1
/// from `#0A0A0A` on `#040404` — the bar's own near-black material, faithfully sampled from a
/// perfectly accurate frame. It is equally wrong for the other checks: a control parked behind a
/// bar cannot be tapped, so its touch target and its missing label are not defects the developer
/// can act on.
///
/// The rule is deliberately conservative, because a wrong skip is invisible in the report. A view
/// occludes only when it is drawn *after* one of the node's ancestors in that ancestor's own
/// `subviews` order, is unhidden and effectively opaque, **fully contains** the node's frame, and
/// is not one of Scyther's own overlays. Partial overlap is not occlusion — culling everything a
/// bar merely touches would throw away the top row of every scrolling screen there is.
///
/// Known limits, stated rather than hidden: `layer.zPosition` is not consulted, so a view reordered
/// by z rather than by index is missed; and a cover that is neither a later sibling of an ancestor
/// nor inside one is not found.
///
/// Two things keep the cost down, because this runs per node inside a 0.25s budget and its shape is
/// quadratic. Siblings are examined topmost-first, since a bar or an overlay is the thing added
/// last and is what the query is looking for — so the budget, when it runs out, has already spent
/// itself on the likeliest covers rather than on the row below. And each level converts the node's
/// frame into that level's own coordinate space *once*, so the per-sibling test is a plain `frame`
/// read rather than a UIKit conversion; only a sibling that passes that pre-filter is measured
/// properly. A transformed sibling's `frame` is UIKit's bounding box of its transformed bounds,
/// which is the same rectangle the accurate test computes, so the pre-filter does not lose one.
///
/// - Parameters:
///   - view: The view whose position in the hierarchy decides what is drawn over it. For a
///     synthetic element this is the view that vends it, since that is where it is drawn.
///   - frame: The node's frame, in `space`.
///   - space: The coordinate space `frame` is expressed in, or `nil` for window coordinates — see
///     ``ScytherPresentation/untransformedMeasurementSpace(for:)``.
/// - Returns: `true` when the node is completely covered.
@MainActor
private func isOccluded(_ view: UIView, frame: CGRect, measuredIn space: UIView?) -> Bool {
    guard !frame.isEmpty else { return false }
    var budget = maximumOcclusionCandidates
    var node = view
    var steps = 0
    while let parent = node.superview, steps < maximumAncestryDepth {
        let subviews = parent.subviews
        guard let index = subviews.firstIndex(where: { $0 === node }) else { return false }
        let inParent = parent.convert(frame, from: space)
        for sibling in subviews[subviews.index(after: index)...].reversed() {
            guard sibling.frame.contains(inParent) else { continue }
            if covers(sibling, frame: frame, measuredIn: space, budget: &budget, depth: 0) {
                return true
            }
            guard budget > 0 else { return false }
        }
        node = parent
        steps += 1
    }
    return false
}

/// Whether `view`, or something inside it, paints over the whole of `frame`.
///
/// Recursive because the view that *contains* the frame is rarely the view that *paints* it: a bar
/// is a transparent container holding a background view holding a blur. The recursion only ever
/// descends into a view that already contains the frame, so a subtree that cannot be covering it is
/// never entered.
///
/// - Parameters:
///   - view: The candidate cover.
///   - frame: The node's frame, in `space`.
///   - space: The coordinate space `frame` is expressed in, or `nil` for window coordinates.
///   - budget: How many more views this query may look at; decremented as it goes.
///   - depth: How far this call has descended into the candidate.
/// - Returns: `true` when the candidate covers the frame with something opaque.
@MainActor
private func covers(_ view: UIView,
                    frame: CGRect,
                    measuredIn space: UIView?,
                    budget: inout Int,
                    depth: Int) -> Bool {
    guard budget > 0, depth <= maximumOcclusionDepth else { return false }
    budget -= 1
    guard !view.isHidden, view.alpha > 0.99 else { return false }
    guard view.auditFrame(measuredIn: space).contains(frame) else { return false }
    guard !view.isScytherOwned else { return false }
    if drawsOpaqueMaterial(view) { return true }
    for subview in view.subviews where covers(subview,
                                              frame: frame,
                                              measuredIn: space,
                                              budget: &budget,
                                              depth: depth + 1) {
        return true
    }
    return false
}

/// Whether a view paints something the content behind it cannot be read through.
///
/// `isOpaque` is not the test: it defaults to `true` on every `UIView` in the process, including
/// the thousands that paint nothing at all, so trusting it would cull most of a screen. What a view
/// *draws* is the honest question, and there are two answers that matter. A background colour at
/// full alpha is one. A `UIVisualEffectView` is the other: a material blurs what is behind it into
/// itself, which is precisely why the contrast sampler reads the material's own near-black instead
/// of the text it was aimed at.
///
/// - Parameter view: The view to test.
/// - Returns: `true` when it paints over what is behind it.
@MainActor
private func drawsOpaqueMaterial(_ view: UIView) -> Bool {
    if view is UIVisualEffectView { return true }
    guard let colour = view.backgroundColor else { return false }
    return colour.cgColor.alpha > 0.99
}

/// Whether a container that is itself out of view still has content the developer can see.
///
/// The walk prunes a whole subtree when its container is not visible, justified by "a subview
/// cannot be visible through a container that is not". ``clippedRegion(for:in:window:includingOwnClip:)``
/// says the opposite in code, and is right to: it intersects only `clipsToBounds` ancestors,
/// because UIKit draws the subviews of a non-clipping view wherever they are laid out. The two
/// rules disagreed exactly where it costs something — a stretchy or parallax header laid out above
/// the window with its content pinned back into view, or an anchor view kept off canvas for
/// constraints, lost every child.
///
/// So a container that does not clip is asked one further question before its subtree is thrown
/// away. A container that *does* clip is not: nothing inside it can be drawn beyond it, which is
/// the same rule the region function applies.
///
/// - Parameters:
///   - view: The container whose own frame missed the visible region.
///   - region: The visible region, in `space`.
///   - space: The coordinate space to measure in, or `nil` for window coordinates.
/// - Returns: `true` when a subview of it can still be seen.
@MainActor
private func vendsContentOutsideItsOwnFrame(_ view: UIView,
                                            region: CGRect,
                                            measuredIn space: UIView?) -> Bool {
    guard !view.clipsToBounds, !region.isNull, !region.isEmpty else { return false }
    for subview in view.subviews.prefix(maximumEscapeCandidates) {
        guard !subview.isHidden, subview.alpha > 0.01 else { continue }
        if region.intersects(subview.auditFrame(measuredIn: space)) { return true }
    }
    return false
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
/// The one case that exception loses is Apple's documented custom-container pattern
/// (`UIAccessibilityContainer.h`): a chart, seat map, calendar grid or keypad that draws its
/// content in `draw(_:)` and vends one `UIAccessibilityElement` per datum from
/// `accessibilityElement(at:)` without ever setting `accessibilityElements`. Reading only
/// `subviews` there collects nothing and reports the screen clean, for precisely the kind of
/// hand-rolled view where accessibility defects actually live.
///
/// Such a view is asked, and only such a view — but "such a view" is decided by
/// ``declaresAccessibilityElements(_:)``, not by having no subviews. The subview count was the
/// wrong discriminator in both directions. It missed every container with a single subview: a chart
/// with a title label, a seat map with a background image, a cell that vends its drawn sub-parts
/// while holding a selected-background view, `MKMapView`. And it sent every *other* leaf — the
/// decorative views, spacers and drawing layers that are the most numerous nodes on any screen —
/// into the one call that is expensive, because a view with no subviews is exactly what most nodes
/// are. Asking whether the class overrides the pair at all is a memoised dictionary lookup, it is
/// what "this view has something of its own to say" actually means, and it keeps the hang shut: a
/// class that has not overridden the pair inherits `NSObject`'s implementation, which is the one
/// that descends the whole view subtree, and it is never called.
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
///   set them; the elements it declares when its class declares any; its `subviews` otherwise.
@MainActor
private func viewChildren(of view: UIView) -> [AuditNode] {
    if view.accessibilityElementsHidden { return [] }
    if let elements = view.accessibilityElements {
        return auditNodes(from: elements)
    }
    if declaresAccessibilityElements(type(of: view)) {
        let declared = declaredElements(of: view)
        if !declared.isEmpty { return declared }
    }
    return honouringModality(view.subviews,
                             searchingDescendants: isWithinReachOfTheWindow(view))
}

/// The answer ``declaresAccessibilityElements(_:)`` has already worked out for a class.
///
/// Sound because a class's method table does not change once it is realised, and bounded because a
/// process contains a fixed set of classes.
@MainActor
private var declaringClasses: [ObjectIdentifier: Bool] = [:]

/// Whether a class implements the `UIAccessibilityContainer` pair itself.
///
/// This is the discriminator that decides whether a view is ever asked to hand over its
/// accessibility children, and the whole hang turns on it. `accessibilityElementCount()` and
/// `accessibilityElement(at:)` are declared on `NSObject`, so *every* object answers them — and
/// `NSObject`'s implementation is the one that computes an accessibility subtree on the spot
/// (`-[NSObject(AXPrivCategory) _accessibilityElements]`, the frame this repo's own hang sample is
/// full of). A class that has overridden them answers from something it already holds instead.
///
/// Comparing implementation pointers against `NSObject`'s is exactly that question, asked of the
/// runtime rather than guessed at from the shape of the hierarchy, and it is one dictionary lookup
/// per node after the first view of each class. The selectors are built by name because
/// `#selector` needs a Swift declaration to point at and these are informal-protocol methods on
/// `NSObject`; the names are the ones in `UIAccessibilityContainer.h` and cannot change without
/// breaking every app that implements them.
///
/// - Parameter type: The class to test.
/// - Returns: `true` when it, or a superclass below `NSObject`, implements either method.
@MainActor
internal func declaresAccessibilityElements(_ type: AnyClass) -> Bool {
    let key = ObjectIdentifier(type)
    if let known = declaringClasses[key] { return known }
    let declares = accessibilityContainerSelectors.contains { selector in
        class_getMethodImplementation(type, selector) != class_getMethodImplementation(NSObject.self, selector)
    }
    declaringClasses[key] = declares
    return declares
}

/// The two methods `UIAccessibilityContainer.h` documents a custom container as implementing.
///
/// Computed rather than stored because a `Selector` is a runtime handle rather than a value Swift 6
/// will let a global hold across actors; it is resolved once per class, not once per node.
private var accessibilityContainerSelectors: [Selector] {
    [NSSelectorFromString("accessibilityElementCount"),
     NSSelectorFromString("accessibilityElementAtIndex:")]
}

/// The children a view vends through `accessibilityElementCount()`/`accessibilityElement(at:)`.
///
/// Only ever called for a view whose class implements that pair — see `viewChildren(of:)` and
/// ``declaresAccessibilityElements(_:)`` for why that condition is what makes asking safe. The
/// count is sanity-checked rather than trusted: `NSObject`'s default implementation answers
/// `NSNotFound` when it has nothing to say, and iterating that would be a hang dressed up as a
/// loop, so anything absurd is treated as "vends nothing".
///
/// - Parameter view: The view to ask.
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
/// report" answer, and `Int.max` to a `for` loop. The size is ``AccessibilityAuditor/maximumNodes``
/// because that is the honest ceiling: the whole array is materialised inside a single
/// ``AuditNode/children`` read, before ``AccessibilityAuditor/collect(root:)`` can count a node or
/// read the clock even once, so a limit larger than the walk's own budget is a cap that cannot fire
/// before the thing it is capping has already happened. A container that really does claim more
/// elements than the entire walk can hold is not believed, and the walk would have truncated inside
/// it in any case.
@MainActor
private var maximumDeclaredElements: Int { AccessibilityAuditor.maximumNodes }

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
/// around hidden, at zero alpha, animated off the window edge or laid out at zero size, and
/// honouring the flag on one of those silently empties the audit for the whole screen — the worst
/// possible failure for a tool whose output is a list of what is wrong, since an empty list reads
/// as "nothing is". That is not a hypothetical: this filter used to decide a modal was live with
/// `!isHidden && alpha > 0.01` while the walk decided visibility with a stricter rule that also
/// culls off-window and clipped content, so a parked sheet passed the first test, discarded every
/// sibling, and was then culled by the second — an empty report under a green tick. There is one
/// visibility rule now, ``AuditNode/isVisible``, and this asks it.
///
/// - Parameters:
///   - children: One container's children, in order.
///   - searchingDescendants: Whether a child that merely *contains* a modal counts as one. See
///     `containsLiveModal(_:budget:depth:)` for why that is asked only near the window.
/// - Returns: Just the modal child when there is one, all of them otherwise.
@MainActor
private func honouringModality<Element: NSObject>(_ children: [Element],
                                                  searchingDescendants: Bool = false) -> [Element] {
    let modal = children.last { child in
        if isLiveModal(child) { return true }
        guard searchingDescendants, let view = child as? UIView else { return false }
        var budget = maximumModalSearchNodes
        return containsLiveModal(view, budget: &budget, depth: 0)
    }
    guard let modal else { return children }
    return [modal]
}

/// Whether an object claims modality *and* can actually be seen.
///
/// One rule, asked of the same ``AuditNode/isVisible`` the walk uses, so a modal this filter honours
/// can never be a node the walk then throws away. A non-view element has no `isHidden` or `alpha` of
/// its own; ``AccessibilityElementNode/isVisible`` answers for it on the same terms as everything
/// else, which is where its container is drawn.
///
/// - Parameter object: The child to test.
/// - Returns: `true` when it is a live modal.
@MainActor
private func isLiveModal(_ object: NSObject) -> Bool {
    guard object.accessibilityViewIsModal else { return false }
    return auditNode(wrapping: object)?.isVisible ?? true
}

/// Whether a live modal is buried somewhere inside `view`.
///
/// UIKit resolves modality against the whole window, and apps put the flag where it belongs — on
/// the dialog — while adding the dialog inside a dimming container, or letting UIKit put a
/// presented controller's view inside a `UITransitionView`. Inspecting one container's immediate
/// children sees the flag in neither shape, so the entire screen behind a dialog was audited and
/// boxed: findings about controls no assistive-technology user can land on, drawn behind the thing
/// covering them.
///
/// Two bounds keep this from becoming the walk's dominant cost, because reading
/// `accessibilityViewIsModal` is a string-keyed dictionary lookup behind a dispatch barrier rather
/// than an ivar read. It is asked only of containers within `maximumModalContainerDepth` of the
/// window — the only place a full-screen presentation can be attached — and it looks at no more
/// than `maximumModalSearchNodes` views per container. A dialog buried deeper than that is not
/// found, which is precisely the behaviour this replaces rather than a new loss.
///
/// - Parameters:
///   - view: The subtree to search. The view itself has already been tested by the caller.
///   - budget: How many more views this search may look at; decremented as it goes.
///   - depth: How far this call has descended.
/// - Returns: `true` when something inside it is a live modal.
@MainActor
private func containsLiveModal(_ view: UIView, budget: inout Int, depth: Int) -> Bool {
    guard budget > 0, depth < maximumModalSearchDepth else { return false }
    for subview in view.subviews {
        budget -= 1
        guard budget > 0 else { return false }
        if isLiveModal(subview) { return true }
        if containsLiveModal(subview, budget: &budget, depth: depth + 1) { return true }
    }
    return false
}

/// How deep a modal search descends into one child.
private let maximumModalSearchDepth = 6

/// How many views a modal search looks at inside one container.
private let maximumModalSearchNodes = 64

/// How far from the window a container may be and still have its descendants searched for a modal.
///
/// A modal presentation is attached at or near the window: the window's own subviews, or one
/// `UITransitionView` below them, or a dimming container an app adds to the window itself. Deeper
/// than that and a "modal" is a component's own dialog, whose siblings are its own subtree rather
/// than the screen.
private let maximumModalContainerDepth = 3

/// Whether `view` is the window or sits within `maximumModalContainerDepth` of it.
///
/// A handful of pointer dereferences, and it is what keeps the descendant search off the thousands
/// of containers deeper in a screen where it would cost an accessibility read per subview.
///
/// - Parameter view: The container about to have its children filtered.
/// - Returns: `true` when a full-screen modal could be attached here.
@MainActor
private func isWithinReachOfTheWindow(_ view: UIView) -> Bool {
    var current: UIView? = view
    var steps = 0
    while let node = current, steps <= maximumModalContainerDepth {
        if node is UIWindow { return true }
        current = node.superview
        steps += 1
    }
    return false
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
        auditFrame(measuredIn: ScytherPresentation.untransformedMeasurementSpace(for: self))
    }

    /// This view's geometry in an already-resolved measurement space.
    ///
    /// Split out of ``frameInWindow`` because resolving that space is a fact about the *screen*
    /// that the walk was paying for three times per node — once in `isVisible`, once in the
    /// `frameInWindow` inside it, and once in the walk's own read — and each of those went on to
    /// walk the presented view-controller chain. Everything that needs several frames in the same
    /// space now resolves it once and passes it down, which is also the only way the region, the
    /// frame and any occluding view are guaranteed to be compared in the same coordinates.
    ///
    /// - Parameter space: The space to measure in, or `nil` for window coordinates.
    /// - Returns: The view's bounds converted into that space.
    fileprivate func auditFrame(measuredIn space: UIView?) -> CGRect {
        guard superview != nil else { return bounds }
        guard let space else { return convert(bounds, to: nil) }
        return convert(bounds, to: space)
    }

    /// Whether any of this view can actually be seen.
    ///
    /// Hidden and near-zero alpha are the easy half: they show nothing for VoiceOver or a sighted
    /// user to perceive, so they are excluded the same way a `0`-sized frame is. The rest is three
    /// separate ways of not being on screen, and the walk prunes the whole subtree below any of
    /// them:
    ///
    /// - **Clipped or off the window.** See `clippedRegion(for:in:window:includingOwnClip:)` for
    ///   the recycled cells, parked screens and clipped carousels this used to report.
    /// - **Laid out beyond a container that does not clip.** The subtree is *not* pruned in that
    ///   case, because UIKit draws such a container's subviews wherever they are laid out — see
    ///   `vendsContentOutsideItsOwnFrame(_:region:measuredIn:)`, which is what makes this rule and
    ///   the region rule agree instead of contradict each other.
    /// - **Covered by something drawn on top.** See `isOccluded(_:frame:measuredIn:)`; this is the
    ///   caption scrolled under a navigation bar that was measured against the bar's own material.
    ///
    /// A view with no window is not clipped by anything and cannot be off the edge of anything, so
    /// it stays visible. That is the not-yet-installed case, and every unit test's case.
    ///
    /// The walk does not ask this: it asks ``frameInWindowIfVisible``, which applies the same three
    /// rules in the same order while sharing the measurement space and the converted frame with the
    /// answer it hands back. This stays as the standalone question — "can any of this be seen" — for
    /// callers that want it without a frame, and because it is the shape every rule here is tested
    /// through. The one thing it does not fold in is the walk's own emptiness guard: a zero-sized
    /// container is still *visible* by this rule, and still not a candidate.
    var isVisible: Bool {
        guard !isHidden, alpha > 0.01 else { return false }
        guard let window else { return true }
        let correction = ScytherPresentation.untransformedMeasurementSpace(for: self)
        let region = clippedRegion(for: self, in: correction ?? window, window: window)
        let frame = auditFrame(measuredIn: correction)
        guard region.intersects(frame) else {
            return vendsContentOutsideItsOwnFrame(self, region: region, measuredIn: correction)
        }
        return !isOccluded(self, frame: frame, measuredIn: correction)
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

    /// The same climb, stopped at an ancestor the walk has already cleared — see
    /// ``AuditNode/isScytherOwned(below:)``.
    ///
    /// - Parameter boundary: A node already known not to be Scyther's.
    /// - Returns: `true` when this view or something above it and below `boundary` is Scyther's.
    func isScytherOwned(below boundary: ObjectIdentifier?) -> Bool {
        isAncestryScytherOwned(startingAt: self, stoppingAt: boundary)
    }

    /// The view itself, which is what its children's responder chains climb through.
    var ownershipIdentity: ObjectIdentifier? { ObjectIdentifier(self) }

    /// The view's frame, or `nil` when nothing of it can be seen.
    ///
    /// The same three rules as ``isVisible``, in the same order, with the measurement space and the
    /// converted frame resolved once and shared between the visibility decision and the answer —
    /// see ``AuditNode/frameInWindowIfVisible`` for why asking the two questions separately cost
    /// two ancestor climbs per node for one pair of answers.
    ///
    /// The cheap tests come first on purpose: a hidden or fully transparent view is decided before
    /// any geometry is resolved at all, which on a screen holding a pool of hidden or recycled
    /// subviews is most of the nodes the walk touches.
    var frameInWindowIfVisible: CGRect? {
        guard !isHidden, alpha > 0.01 else { return nil }
        let space = ScytherPresentation.untransformedMeasurementSpace(for: self)
        let frame = auditFrame(measuredIn: space)
        guard !frame.isEmpty else { return nil }
        // A view with no window is not clipped by anything and cannot be off the edge of anything.
        // That is the not-yet-installed case, and every unit test's case.
        guard let window else { return frame }
        let region = clippedRegion(for: self, in: space ?? window, window: window)
        guard region.intersects(frame) else {
            return vendsContentOutsideItsOwnFrame(self, region: region, measuredIn: space) ? frame : nil
        }
        return isOccluded(self, frame: frame, measuredIn: space) ? nil : frame
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
        return frame(in: window,
                     measuredIn: ScytherPresentation.untransformedMeasurementSpace(for: container))
    }

    /// The element's frame, given a container's window and an already-resolved measurement space.
    ///
    /// Split out for the same reason `auditFrame(measuredIn:)` is: `isVisible` needs the
    /// frame *and* the region *and* any occluding view expressed in one space, and resolving that
    /// space — along with the container view at the top of this element's container chain — used to
    /// be repeated for each of them. A synthetic element paid it worst: `isVisible` resolved the
    /// container, then called `frameInWindow`, which resolved the whole chain again.
    ///
    /// - Parameters:
    ///   - window: The window the container is installed in.
    ///   - space: The space to measure in, or `nil` for window coordinates.
    /// - Returns: The element's frame in that space.
    private func frame(in window: UIWindow, measuredIn space: UIView?) -> CGRect {
        let inWindow = window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace)
        guard let space else { return inWindow }
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
    ///
    /// Occlusion is asked against the container as well, and for the same reason: an element is
    /// drawn where its container is, so anything painted over that spot hides the element too. That
    /// is how a SwiftUI caption scrolled under a navigation bar is skipped rather than measured
    /// against the bar's material.
    var isVisible: Bool {
        guard let container = resolveContainerView(forContainerChainOf: element),
              let window = container.window else {
            return true
        }
        let correction = ScytherPresentation.untransformedMeasurementSpace(for: container)
        let region = clippedRegion(for: container,
                                   in: correction ?? window,
                                   window: window,
                                   includingOwnClip: true)
        let frame = frame(in: window, measuredIn: correction)
        guard region.intersects(frame) else { return false }
        return !isOccluded(container, frame: frame, measuredIn: correction)
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

    /// The same climb, stopped at an ancestor the walk has already cleared.
    ///
    /// A synthetic element's chain is `accessibilityContainer` links, which an app sets and which
    /// need not lead back to the node that vended this one — so the boundary is often never
    /// reached and the climb runs in full, exactly as it did before. That is the safe direction:
    /// stopping early can only skip links a previous climb has already tested.
    ///
    /// - Parameter boundary: A node already known not to be Scyther's.
    /// - Returns: `true` when this element or something above it and below `boundary` is Scyther's.
    func isScytherOwned(below boundary: ObjectIdentifier?) -> Bool {
        isAncestryScytherOwned(startingAt: element, stoppingAt: boundary)
    }

    /// The wrapped element, which is what its own children's container chains climb through.
    var ownershipIdentity: ObjectIdentifier? { ObjectIdentifier(element) }

    /// The element's frame, or `nil` when nothing of it can be seen.
    ///
    /// The fused form of ``frameInWindow`` and ``isVisible`` — see
    /// ``AuditNode/frameInWindowIfVisible``. A synthetic element paid for the split worse than a
    /// view did: `isVisible` resolved the container chain and the measurement space, then called
    /// `frameInWindow`, which resolved both again from scratch.
    var frameInWindowIfVisible: CGRect? {
        guard let container = resolveContainerView(forContainerChainOf: element),
              let window = container.window else {
            let frame = element.accessibilityFrame
            return frame.isEmpty ? nil : frame
        }
        let correction = ScytherPresentation.untransformedMeasurementSpace(for: container)
        let frame = frame(in: window, measuredIn: correction)
        guard !frame.isEmpty else { return nil }
        let region = clippedRegion(for: container,
                                   in: correction ?? window,
                                   window: window,
                                   includingOwnClip: true)
        guard region.intersects(frame) else { return nil }
        return isOccluded(container, frame: frame, measuredIn: correction) ? nil : frame
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
