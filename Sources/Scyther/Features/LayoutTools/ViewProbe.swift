//
//  ViewProbe.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

import UIKit

/// Finds the host view under a point, so the ruler can snap to something real.
///
/// Deliberately not `UIView.hitTest(_:with:)`. That method answers "which view would receive
/// this touch", which is a different question: it respects `isUserInteractionEnabled`, so it
/// skips the labels and image views a developer most wants to measure, and it has no notion of
/// Scyther's own interface being off-limits.
///
/// **This must never read an accessibility property.** Asking a `UIView` for its accessibility
/// children makes UIAccessibility compute that view's subtree recursively. Doing so across a
/// real hierarchy is quadratic and hung the app when the accessibility audit shipped — and the
/// audit ran once per navigation, where this runs once per touch-move.
@MainActor
enum ViewProbe {

    /// The deepest visible host view containing `point`.
    ///
    /// Front-to-back, deepest match wins: a developer pointing at a label means the label, not
    /// the stack that contains it.
    ///
    /// Skips any view that is hidden, fully transparent, or one of Scyther's own. Ownership is
    /// answered by ``AuditNode/isScytherOwned``, which `UIView` already conforms to — a rule that
    /// is memoised by class and was rewritten once after a name-based version let the audit draw
    /// over Scyther's own close button. Reading it here rather than writing a second test is what
    /// keeps the two from drifting apart.
    ///
    /// **Known limitation, matching UIKit's own `hitTest(_:with:)`.** Descending into a subview is
    /// gated on the point falling inside *that subview's own* `bounds`, even when the subview does
    /// not clip. A grandchild that visually overflows its immediate, non-clipping parent — a badge
    /// pinned at a negative inset, say — is unreachable once the point lands outside the parent's
    /// bounds, even though the badge is genuinely on screen there. This is platform-consistent
    /// rather than a bug to fix here, but it means the ruler can decline to measure something a
    /// developer can plainly see; there is no cheap general fix, since finding an overflowing
    /// descendant would mean testing every subview's actual painted frame rather than pruning by
    /// containment.
    ///
    /// - Parameters:
    ///   - point: The point, in `root`'s coordinate space.
    ///   - root: The view to search. The ruler passes its window.
    /// - Returns: The deepest match, or `nil` when `point` is outside `root` or `root` is itself
    ///   skipped.
    static func view(at point: CGPoint, in root: UIView) -> UIView? {
        guard root.bounds.contains(point), isEligible(root) else { return nil }

        for subview in root.subviews.reversed() {
            let converted = root.convert(point, to: subview)
            if let deeper = view(at: converted, in: subview) { return deeper }
        }

        return root
    }

    /// Whether a view can be measured against at all.
    ///
    /// Separate from the walk so the rule reads as one thing rather than three conditions inside
    /// a loop, and so a reader can see immediately that none of it touches accessibility.
    ///
    /// - Parameter view: The view to test.
    private static func isEligible(_ view: UIView) -> Bool {
        !view.isHidden && view.alpha > 0.01 && !view.isScytherOwned
    }
}
