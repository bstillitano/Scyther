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
    /// The screen outline, letterboxed to fit `box` while keeping the window's proportions.
    ///
    /// Stretching the outline to fill the box would misreport every position on it, which is the
    /// one thing this drawing exists to get right.
    ///
    /// - Parameters:
    ///   - windowBounds: The window the frames are measured in.
    ///   - box: The space available to draw in.
    /// - Returns: The outline's rect within `box`, or `.zero` for a degenerate window.
    static func outlineRect(forWindowBounds windowBounds: CGRect, in box: CGSize) -> CGRect {
        guard windowBounds.width > 0, windowBounds.height > 0 else { return .zero }

        let scale = min(box.width / windowBounds.width, box.height / windowBounds.height)
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
    /// of the screen, and drawing them identically would say it was.
    ///
    /// - Parameters:
    ///   - frameInWindow: The view's frame in window space.
    ///   - windowBounds: The window the frame is measured in.
    ///   - box: The space available to draw in.
    /// - Returns: The frame's rect within `box`, or `.zero` for a degenerate window.
    static func rect(for frameInWindow: CGRect, windowBounds: CGRect, in box: CGSize) -> CGRect {
        guard windowBounds.width > 0, windowBounds.height > 0 else { return .zero }

        let outline = outlineRect(forWindowBounds: windowBounds, in: box)
        let scale = min(box.width / windowBounds.width, box.height / windowBounds.height)

        return CGRect(x: outline.minX + (frameInWindow.minX - windowBounds.minX) * scale,
                      y: outline.minY + (frameInWindow.minY - windowBounds.minY) * scale,
                      width: frameInWindow.width * scale,
                      height: frameInWindow.height * scale)
    }
}
#endif
