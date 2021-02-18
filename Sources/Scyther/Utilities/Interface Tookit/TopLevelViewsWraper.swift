//
//  File.swift
//
//
//  Created by Brandon Stillitano on 18/2/21.
//

import NotificationCenter
import UIKit

/// `TopLevelViewsWrapper` is a `UIView` instance that keeps all the views that are meant to stay on top of the screen at all times as its subviews.
class TopLevelViewsWrapper: UIView {
    // MARK: - Data
    var topLevelViews: [TopLevelView] = []

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
            var isSubviewVisible = !view.isHidden
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

    func updateFrame() {
        let screenSize: CGSize = UIScreen.main.bounds.size
        frame = CGRect(x: 0,
                       y: 0,
                       width: screenSize.width,
                       height: screenSize.height)
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
