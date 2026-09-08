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
    /// **A view that paints nothing at the point is passed over in favour of one that does.** This
    /// is not a refinement; without it the ruler does not work on iOS 26 at all. A plain SwiftUI
    /// `TabView` installs `FloatingBarHostingView<FloatingBarContainer>` — a full-screen, fully
    /// opaque-by-`alpha`, entirely unpainted container hosting the floating tab bar — in front of
    /// the app's whole content. It is not hidden, not transparent by `alpha`, and not Scyther's, so
    /// every one of the skip rules above passes it, and the deepest-match rule then returns *it*
    /// for every point on the screen: measured by hand on the example app, a drag between two rows
    /// reported `FloatingBarHostingView<FloatingBarContainer>.left → FloatingBarHostingView<FloatingBarContainer>.left`
    /// and snapped both ends to the screen's left edge. Every iOS 26 app with a tab bar has one.
    ///
    /// So the walk runs twice. The first pass accepts only a view that paints — a background
    /// colour with any opacity, rendered layer contents, a border, or a shadow — which is the
    /// cheap, stored-property approximation of "the developer can see this here". The second pass
    /// runs only when the first found nothing anywhere under the point, and reproduces the
    /// original rule exactly, so a hierarchy of bare, unpainted views still answers rather than
    /// declining. Two passes rather than one comparison because the preference is not local: the
    /// painting view can be *behind* the unpainted one, several siblings back, and there is no way
    /// to know that without looking.
    ///
    /// - Parameters:
    ///   - point: The point, in `root`'s coordinate space.
    ///   - root: The view to search. The ruler passes its window.
    /// - Returns: The deepest match, or `nil` when `point` is outside `root` or `root` is itself
    ///   skipped.
    static func view(at point: CGPoint, in root: UIView) -> UIView? {
        view(at: point, in: root, requiringPaint: true) ?? view(at: point, in: root, requiringPaint: false)
    }

    /// One pass of the walk.
    ///
    /// - Parameters:
    ///   - point: The point, in `root`'s coordinate space.
    ///   - root: The view to search.
    ///   - requiringPaint: Whether a view may only be returned as the match when it paints
    ///     something itself. Descending is never gated on it: an unpainted container is exactly
    ///     what the painted view is usually inside.
    /// - Returns: The deepest acceptable match, or `nil` when there is none.
    private static func view(at point: CGPoint, in root: UIView, requiringPaint: Bool) -> UIView? {
        guard root.bounds.contains(point), isEligible(root) else { return nil }

        for subview in root.subviews.reversed() {
            let converted = root.convert(point, to: subview)
            if let deeper = view(at: converted, in: subview, requiringPaint: requiringPaint) { return deeper }
        }

        return requiringPaint && !paints(root) ? nil : root
    }

    /// Whether a view puts anything of its own on screen.
    ///
    /// Four stored properties, in the order they are cheapest and most often decisive. None of
    /// them is a measurement of pixels, and none can be: reading back what a view actually
    /// rendered means rasterising it, which is the sort of cost the accessibility audit's history
    /// says has no place on a per-touch-move path. This is an approximation, and where it is wrong
    /// it is wrong in the safe direction — a view it fails to recognise as painting is not skipped,
    /// only deprioritised, and if nothing under the point is recognised the second pass returns the
    /// deepest view regardless.
    ///
    /// `backgroundColor` is read through its `cgColor`'s alpha rather than tested for `nil`,
    /// because `.clear` is a background colour that paints nothing and is extremely common on
    /// exactly the container views this rule exists to pass over. It is also why `layer.contents`
    /// is the clause that carries this rule in production rather than a fallback: a `UILabel`'s
    /// background is `.clear`, not `nil`, so a rendered label qualifies *only* through its
    /// `CABackingStore` — which is exactly the spec's own example of what a developer means to
    /// measure.
    ///
    /// **Known limit, named rather than fixed: content drawn by a sublayer.** A view whose visible
    /// content comes from a `CAShapeLayer`, `CAGradientLayer` or `CATextLayer` it hosts — rather
    /// than from its own layer — has no background, no `contents`, no border and no shadow, and is
    /// deprioritised behind whatever painted ancestor is under the point. It is the most common way
    /// this approximation will be wrong. There is no cheap discriminator for it: every container
    /// view's layer has sublayers, one per subview, so "has sublayers" says nothing, and telling a
    /// drawing sublayer from a subview's backing layer means inspecting each one's class and its own
    /// paint properties on a per-touch-move path. The failure it produces is the safe one — the
    /// nearest thing that is visibly there — so it is documented rather than guessed at.
    ///
    /// - Parameter view: The view to test.
    /// - Returns: `true` when the view has a visible background, rendered contents, a border, or a
    ///   shadow of its own.
    private static func paints(_ view: UIView) -> Bool {
        if let background = view.backgroundColor, background.cgColor.alpha > 0 { return true }
        if view.layer.contents != nil { return true }
        if view.layer.borderWidth > 0, (view.layer.borderColor?.alpha ?? 0) > 0 { return true }
        if view.layer.shadowOpacity > 0 { return true }
        return false
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
