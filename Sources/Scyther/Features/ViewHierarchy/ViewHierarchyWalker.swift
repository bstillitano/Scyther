//
//  ViewHierarchyWalker.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// Builds a ``ViewHierarchySnapshot`` from a live view hierarchy.
///
/// **Everything this reads is a cheap stored property**: `subviews`, `bounds`, `isHidden`,
/// `alpha`, and a text property on the three concrete types ``TextCarryingView`` whitelists.
/// It must never touch the accessibility tree. Asking a `UIView` for its accessibility children
/// forces `UIAccessibility` to compute a subtree recursively, which is what hung this app in
/// 4.3.0 — and a hierarchy walk is that mistake's natural home.
///
/// Recursion is deliberately unbounded, unlike ``AccessibilityAuditor``'s depth and node caps.
/// Those exist because one link the audit climbs — `accessibilityContainer` — is an app-settable
/// weak reference that can point back at itself, a genuine cycle `subviews` cannot form. A
/// hierarchy deep enough to overflow this walk would already have broken UIKit's own recursive
/// layout and hit-testing, so a cap here would only silently truncate a real tree to defend
/// against one that cannot exist.
@MainActor
enum ViewHierarchyWalker {
    /// Walks the key window.
    ///
    /// - Parameter window: The window to snapshot.
    /// - Returns: The snapshot.
    static func snapshot(of window: UIWindow) -> ViewHierarchySnapshot {
        snapshot(of: window, windowBounds: window.bounds)
    }

    /// Walks any root, measuring against the bounds given.
    ///
    /// Split from ``snapshot(of:)-(UIWindow)`` so the rules can be exercised against a synthetic
    /// hierarchy without standing up a window.
    ///
    /// The root itself is never ownership-tested — only its subviews are, before the walk
    /// recurses into them. In production `root` is always the key window, which is never
    /// Scyther's, so this is a deliberate trust rather than a gap: ownership is a rule about what
    /// the walk descends *into*, not about the view the caller chose to start from.
    ///
    /// - Parameters:
    ///   - root: The view to walk.
    ///   - windowBounds: The bounds every frame is converted into and measured against.
    ///   - isOwned: The ownership test, given the candidate view and the nearest ancestor already
    ///     known not to be Scyther's. Defaults to the shared ``AuditNode/isScytherOwned(below:)``
    ///     rule; injectable only because that member lives on an extension and cannot be
    ///     overridden by a test subclass.
    /// - Returns: The snapshot.
    static func snapshot(
        of root: UIView,
        windowBounds: CGRect,
        isOwned: (UIView, ObjectIdentifier?) -> Bool = { $0.isScytherOwned(below: $1) }
    ) -> ViewHierarchySnapshot {
        var views: [ObjectIdentifier: UIView] = [:]

        func node(for view: UIView, depth: Int, ancestorsHidden: Bool) -> ViewNode {
            // `bounds`, never `frame`: Apple documents `frame` as undefined when `transform` is
            // not the identity, so a view mid-animation, a scaled view, or a scroll view's
            // content view under `zoomScale` would be reported at coordinates UIKit does not
            // define — in the one tool built to say where a view is. `convert(bounds, from:)` is
            // defined in every case and identical to the `frame` form whenever no transform is
            // involved, which is why both ``AuditNode/frameInWindow`` and `LayoutRuler` already
            // convert bounds. The root falls out of the same expression rather than needing a
            // case of its own: converting a view's bounds from itself to itself is its bounds.
            let frame = root.convert(view.bounds, from: view)
            let hidden = ancestorsHidden || view.isHidden || view.alpha <= 0.01
            let identity = ObjectIdentifier(view)

            // `view` reaches this point only once it is already known not to be Scyther's — it
            // is either `root`, which is trusted, or a subview that has already passed the
            // filter below in its parent's call. So its own identity is a sound boundary for the
            // climb each of its children makes: the shared rule only needs to test the single
            // link between a child and this view, not re-climb the chain all the way to the
            // window, which is what made the unbounded default quadratic in the depth of the
            // screen. See ``AuditNode/isScytherOwned(below:)`` for why the shortcut holds.
            let children = view.subviews
                .filter { !isOwned($0, identity) }
                .map { node(for: $0, depth: depth + 1, ancestorsHidden: hidden) }

            views[identity] = view

            return ViewNode(id: identity,
                            className: String(describing: type(of: view)),
                            frameInWindow: frame,
                            depth: depth,
                            text: TextCarryingView(view)?.text,
                            isHidden: hidden,
                            isZeroSize: frame.width == 0 || frame.height == 0,
                            isOffScreen: !frame.intersects(windowBounds),
                            children: children)
        }

        let tree = node(for: root, depth: 0, ancestorsHidden: false)
        return ViewHierarchySnapshot(root: tree, views: views)
    }
}
#endif
