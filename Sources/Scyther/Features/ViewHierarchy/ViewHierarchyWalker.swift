//
//  ViewHierarchyWalker.swift
//  Scyther
//

#if !os(macOS)
import UIKit

/// Builds a ``ViewHierarchySnapshot`` from a live view hierarchy.
///
/// **Everything this reads is a cheap stored property**: `subviews`, `frame`, `isHidden`,
/// `alpha`, and a text property on two concrete types. It must never touch the accessibility
/// tree. Asking a `UIView` for its accessibility children forces `UIAccessibility` to compute a
/// subtree recursively, which is what hung this app in 4.3.0 — and a hierarchy walk is that
/// mistake's natural home.
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
    /// - Parameters:
    ///   - root: The view to walk.
    ///   - windowBounds: The bounds every frame is converted into and measured against.
    ///   - isOwned: The ownership test. Defaults to the shared ``AuditNode/isScytherOwned`` rule;
    ///     injectable only because that property lives on an extension and cannot be overridden
    ///     by a test subclass.
    /// - Returns: The snapshot.
    static func snapshot(of root: UIView,
                         windowBounds: CGRect,
                         isOwned: (UIView) -> Bool = { $0.isScytherOwned }) -> ViewHierarchySnapshot {
        var views: [ObjectIdentifier: UIView] = [:]

        func node(for view: UIView, depth: Int, ancestorsHidden: Bool) -> ViewNode {
            let frame = view.superview.map { $0.convert(view.frame, to: root) } ?? view.frame
            let hidden = ancestorsHidden || view.isHidden || view.alpha <= 0.01

            let children = view.subviews
                .filter { !isOwned($0) }
                .map { node(for: $0, depth: depth + 1, ancestorsHidden: hidden) }

            views[ObjectIdentifier(view)] = view

            return ViewNode(id: ObjectIdentifier(view),
                            className: String(describing: type(of: view)),
                            frameInWindow: frame,
                            depth: depth,
                            text: text(of: view),
                            isHidden: hidden,
                            isZeroSize: frame.width == 0 || frame.height == 0,
                            isOffScreen: !frame.intersects(windowBounds),
                            children: children)
        }

        let tree = node(for: root, depth: 0, ancestorsHidden: false)
        return ViewHierarchySnapshot(root: tree, views: views)
    }

    /// Text the view carries itself.
    ///
    /// Read from concrete types only. An accessibility label would be a richer answer and is
    /// exactly the property this walk must not touch.
    ///
    /// - Parameter view: The view to read.
    /// - Returns: Its text, or `nil`.
    private static func text(of view: UIView) -> String? {
        switch view {
        case let label as UILabel: return label.text
        case let button as UIButton: return button.currentTitle
        case let field as UITextField: return field.text
        default: return nil
        }
    }
}
#endif
