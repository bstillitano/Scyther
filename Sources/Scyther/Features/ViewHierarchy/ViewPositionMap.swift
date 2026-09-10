//
//  ViewPositionMap.swift
//  Scyther
//

#if !os(macOS)
import CoreGraphics

/// Places a view's frame on a scaled outline of the screen.
///
/// Pure, because this is arithmetic with a right answer and a `View`'s drawing is not something
/// a test can inspect. The page draws what this returns and decides nothing.
enum ViewPositionMap {
    /// How much of each edge of the box is left free around the screen outline, as a fraction of
    /// that edge.
    ///
    /// The outline deliberately does **not** fill the box. A frame outside the window maps
    /// outside the outline — that is the whole point of the no-clamp rule in
    /// ``rect(for:windowBounds:in:)`` — and an outline drawn edge to edge leaves nowhere for
    /// "outside" to be: a view just below the fold maps past the edge of the canvas and is
    /// clipped away, so the reader sees an outline with no mark on it and reads that as "this
    /// view has no position" rather than "this view is off the bottom". That is the one case the
    /// no-clamp rule exists to serve, so it is the one case that must be visible.
    ///
    /// A tenth of each edge is enough for the near misses that matter: a view up to a quarter of
    /// a screen outside the window still lands inside the box. A frame far enough away still
    /// leaves the box entirely, and that is accepted rather than solved — shrinking the outline
    /// until any frame fits would make the ordinary on-screen case unreadable for the sake of a
    /// case the reader already has an exact answer for, since the `Frame` row states it in points.
    /// The map's job is "roughly where", not "precisely how far".
    static let outlineInset: CGFloat = 0.1

    /// The screen outline, letterboxed to fit the box's inset interior while keeping the window's
    /// proportions.
    ///
    /// Stretching the outline to fill the box would misreport every position on it, which is the
    /// one thing this drawing exists to get right.
    ///
    /// - Parameters:
    ///   - windowBounds: The window the frames are measured in.
    ///   - box: The space available to draw in.
    /// - Returns: The outline's rect, centred in `box` with ``outlineInset`` free around it, or
    ///   `.zero` for a degenerate window.
    static func outlineRect(forWindowBounds windowBounds: CGRect, in box: CGSize) -> CGRect {
        guard windowBounds.width > 0, windowBounds.height > 0 else { return .zero }

        let scale = scale(forWindowBounds: windowBounds, in: box)
        let size = CGSize(width: windowBounds.width * scale, height: windowBounds.height * scale)
        return CGRect(x: (box.width - size.width) / 2,
                      y: (box.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }

    /// A window-space frame mapped onto the outline.
    ///
    /// A frame outside the window maps outside the outline and is **not** clamped to its edge:
    /// a view nine hundred points below the fold is not the same answer as a view at the bottom
    /// of the screen, and drawing them identically would say it was. ``outlineInset`` is what
    /// gives the near misses somewhere to be drawn.
    ///
    /// - Parameters:
    ///   - frameInWindow: The view's frame in window space.
    ///   - windowBounds: The window the frame is measured in.
    ///   - box: The space available to draw in.
    /// - Returns: The frame's rect within `box`, or `.zero` for a degenerate window.
    static func rect(for frameInWindow: CGRect, windowBounds: CGRect, in box: CGSize) -> CGRect {
        guard windowBounds.width > 0, windowBounds.height > 0 else { return .zero }

        let outline = outlineRect(forWindowBounds: windowBounds, in: box)
        let scale = scale(forWindowBounds: windowBounds, in: box)

        return CGRect(x: outline.minX + (frameInWindow.minX - windowBounds.minX) * scale,
                      y: outline.minY + (frameInWindow.minY - windowBounds.minY) * scale,
                      width: frameInWindow.width * scale,
                      height: frameInWindow.height * scale)
    }

    /// How many points of box there are to a point of window.
    ///
    /// One function, called by both of the above, because the outline and the frames drawn on it
    /// are only comparable while they share a scale — two copies of this expression is how they
    /// would come to stop sharing one.
    ///
    /// - Parameters:
    ///   - windowBounds: The window the frames are measured in.
    ///   - box: The space available to draw in.
    /// - Returns: The scale, measured against the box's inset interior.
    private static func scale(forWindowBounds windowBounds: CGRect, in box: CGSize) -> CGFloat {
        let interior = CGSize(width: box.width * (1 - 2 * outlineInset),
                              height: box.height * (1 - 2 * outlineInset))
        return min(interior.width / windowBounds.width, interior.height / windowBounds.height)
    }
}
#endif
