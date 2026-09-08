//
//  TopLevelViewsWrapper.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if !os(macOS)
import NotificationCenter
import UIKit

/// A container view that keeps debugging overlays on top of all other content.
///
/// `TopLevelViewsWrapper` manages ``TopLevelView`` instances and ensures they remain
/// visible above all other views in the window hierarchy. It handles:
/// - Adding and managing top-level debug views
/// - Responding to device orientation changes
/// - Pass-through touch handling (only intercepts touches on visible subviews)
/// - Automatic visibility management based on subview visibility
///
/// Its own frame tracks the window it is installed in structurally — `autoresizingMask` plus
/// `layoutSubviews()` — rather than solely through `deviceDidChangeOrientation`'s notification.
/// That notification is unreliable for this: it fires on *any* device-orientation change,
/// including ones that are not interface rotations at all (face-up, face-down), and it carries
/// no guarantee that `UIScreen.main.bounds` — what `updateFrame()` used to read — has caught up
/// to the new orientation by the time it runs. Measured directly, by logging `UIScreen.main.bounds`
/// from inside the notification handler through a rotate-right/rotate-left round trip: it is one
/// rotation *behind* throughout — correct-looking on the first rotation only because the value
/// happened to still match the starting orientation, then stale in the other direction on the
/// way back, leaving every child claiming the *previous* orientation's size once the round trip
/// completed. `autoresizingMask` sidesteps the notification
/// entirely: UIKit applies it synchronously against the window's own bounds at the moment the
/// window actually resizes, which is the real event, not a loosely-coupled signal about it.
/// A `TopLevelView` added to this wrapper — see ``LayoutGuidesView``, which follows this same
/// window→wrapper→view chain with its own `autoresizingMask` — inherits that correctness for
/// free, since its superview is now reliably the right size whenever it is asked.
///
/// - Note: This is an internal class used by ``InterfaceToolkit``.
class TopLevelViewsWrapper: UIView {
    // MARK: - Data
    var topLevelViews: [TopLevelView] = []

    /// `bounds` as of the last time this wrapper propagated a resize to ``topLevelViews``, so
    /// ``layoutSubviews()`` can tell a layout pass that changed nothing about this wrapper's own
    /// size from one that did.
    private var lastPropagatedBounds: CGRect = .zero

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        commonInit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        updateFrame()
        registerForNotifications()
        updateVisibility()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for view: UIView in subviews {
            if view.hitTest(point, with: event) != nil {
                return true
            }
        }
        return false
    }

    func updateVisibility() {
        var shouldBeVisible: Bool = false
        for view: UIView in subviews {
            let isSubviewVisible = !view.isHidden
            shouldBeVisible |= isSubviewVisible
        }
        isHidden = !shouldBeVisible
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view == self ? nil : view
    }
}

// MARK: - Adding Views
extension TopLevelViewsWrapper {
    /// Adds a view that is meant to stay on top of the screen at all times.
    /// - Parameter topLevelView: The view that will be kept on top of the screen.
    func addTopLevelView(topLevelView: TopLevelView) {
        topLevelView.delegate = self
        topLevelViews.append(topLevelView)
        addSubview(topLevelView)
    }
}

// MARK: - Updating Frame
extension TopLevelViewsWrapper {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateFrame()
    }

    /// Repaints ``topLevelViews`` whenever a layout pass leaves this wrapper an actually
    /// different size.
    ///
    /// The structural counterpart to `autoresizingMask`, and what makes every child correct on
    /// a real resize independent of whether — or when — `deviceDidChangeOrientation`'s
    /// notification happens to fire. `autoresizingMask` alone keeps this wrapper's own `frame`
    /// right; it does nothing for children like ``GridOverlayView`` and ``FPSCounterView`` that
    /// have no `autoresizingMask`/`layoutSubviews()` of their own and depend entirely on being
    /// told — this is that telling, driven by the wrapper's own genuine resize rather than by a
    /// notification about the device.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastPropagatedBounds else { return }
        lastPropagatedBounds = bounds
        for view: TopLevelView in topLevelViews {
            view.updateFrame()
        }
    }

    /// Sizes this wrapper to the window it is installed in.
    ///
    /// Reads `window?.bounds` rather than `UIScreen.main.bounds` — see this type's own doc
    /// comment for why the latter is not safe to read from an orientation-change notification.
    /// `window.bounds` is the coordinate space actually being laid out, so once this wrapper is
    /// installed, `autoresizingMask` keeps it correct by construction on every real resize; this
    /// is only the fallback for the moment before it has a window at all, where `UIScreen.main.bounds`
    /// is at least a usable guess.
    func updateFrame() {
        frame = window?.bounds ?? UIScreen.main.bounds
    }
}

// MARK: - Rotation Notifications
extension TopLevelViewsWrapper {
    func registerForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceDidChangeOrientation(notification:)),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }

    /// Propagates a device-orientation change to every child directly, as a best-effort signal
    /// alongside — not instead of — ``layoutSubviews()``'s structural propagation above.
    ///
    /// Kept, and still calling `updateFrame()` on both this wrapper and every child, because
    /// some of those children have no `autoresizingMask` of their own — see ``GridOverlayView``,
    /// which sizes itself from `UIScreen.main.bounds` directly, unrelated to this wrapper's own
    /// frame — and this notification is the only signal they were ever given. Not relied on for
    /// *this* wrapper's own correctness any more, since that now comes from ``layoutSubviews()``,
    /// but removing it would leave those other overlays with no update path at all.
    @objc
    func deviceDidChangeOrientation(notification: NSNotification) {
        if superview?.isKind(of: UIWindow.self) ?? false {
            updateFrame()
            for view: TopLevelView in topLevelViews {
                view.updateFrame()
            }
        }
    }
}

// MARK: - TopLevelViewDelegate
extension TopLevelViewsWrapper: TopLevelViewDelegate {
    func topLevelView(topLevelView: TopLevelView, didUpdateVisibility isHidden: Bool) {
        updateVisibility()
    }
}
#endif
