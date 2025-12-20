//
//  TopLevelView.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if !os(macOS)
import UIKit

/// A delegate protocol for receiving visibility change notifications from a ``TopLevelView``.
protocol TopLevelViewDelegate: AnyObject {
    /// Called when the view's visibility changes.
    ///
    /// - Parameters:
    ///   - topLevelView: The view whose visibility changed.
    ///   - isHidden: The new visibility state.
    func topLevelView(topLevelView: TopLevelView, didUpdateVisibility isHidden: Bool)
}

/// A base class for views that should remain on top of all other content.
///
/// `TopLevelView` is used by Scyther's UI debugging tools (grid overlay, touch visualiser)
/// to ensure they remain visible above the app's content. Subclasses must override
/// ``updateFrame()`` to handle layout changes.
///
/// - Note: This is an internal class used by ``TopLevelViewsWrapper``.
class TopLevelView: UIView {
    // MARK: - Delegate

    /// The delegate to notify when visibility changes.
    weak var delegate: TopLevelViewDelegate?

    /// Called when the superview's frame changes (e.g., after device rotation).
    ///
    /// Subclasses must override this method to update their layout.
    /// The default implementation triggers an assertion failure.
    func updateFrame() {
        assert(false, "Should be overriden in a subclass.")
    }

    override var isHidden: Bool {
        get {
            return super.isHidden
        }
        set {
            super.isHidden = newValue
            delegate?.topLevelView(topLevelView: self, didUpdateVisibility: newValue)
        }
    }
}
#endif
