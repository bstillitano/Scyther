//
//  File.swift
//
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

public class TouchVisualiser: NSObject {
    // MARK: - Data
    private var enabled = false
    public var config: TouchVisualiserConfiguration = TouchVisualiserConfiguration()
    private var touchViews: [TouchView] = []
    private var previousLog = ""

    // MARK: - Lifecycle
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Singleton
    internal static let instance = TouchVisualiser()
    private override init() {
        super.init()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        validateEnvironment()
    }

    // MARK: - Functions
    internal func start() {
        //Set data
        if config.loggingEnabled {
            logMessage("TouchVisualiser: Starting")
        }
        enabled = true
        removeAllTouchViews()

        //Log successful startup
        if config.loggingEnabled {
            logMessage("TouchVisualiser: Started")
        }
    }

    internal func stop() {
        //Set Data
        if config.loggingEnabled {
            logMessage("TouchVisualiser: Stopping")
        }
        enabled = false
        removeAllTouchViews()

        //Log successful shutdown
        if config.loggingEnabled {
            logMessage("TouchVisualiser: Stopped")
        }
    }

    // MARK: - Helper Functions
    internal func removeAllTouchViews() {
        for view in self.touchViews {
            view.removeFromSuperview()
        }
        if let window = UIApplication.shared.keyWindow {
            for subview in window.subviews {
                if let subview = subview as? TouchView {
                    subview.removeFromSuperview()
                }
            }
        }
    }

    internal func validateEnvironment() {
        if AppEnvironment.isSimulator {
            logMessage("TouchVisualiser: Touch radius doesn't work on the simulator because it is not possible to read touch radius on it.")
        }
    }
}

// MARK: - Touch view recycling
extension TouchVisualiser {
    /// Retrieves the first item in the `touchViews` array whose superview is nil. If none available, constructs a `TouchView` and returns it
    private var dequeueTouchView: TouchView? {
        var touchView: TouchView? = touchViews.first(where: { $0.superview == nil })
        if touchView == nil {
            touchView = TouchView()
            touchViews.append(touchView ?? TouchView())
        }
        return touchView
    }

    /// Retrieves the corresponding `TouchView` object for a given `UITouch`.
    /// - Parameter touch: `UITouch` object representing a touch on the screen
    /// - Returns: A nullable `TouchView` object representing a physical screen touch.
    private func findTouchView(_ touch: UITouch) -> TouchView? {
        return touchViews.first(where: { touch == $0.touch })
    }

    /// Displays touches on the screen for a given `UIEvent`.
    /// - Parameter event: `UIEvent` representing a touch on the screen.
    internal func handleEvent(_ event: UIEvent) {
        //Determine whether or not the event should be handled by Scyther.
        guard TouchVisualiser.instance.enabled && event.type == .touches else {
            return
        }

        //Get top most key window
        guard var topWindow = UIApplication.shared.keyWindow else {
            return
        }
        UIApplication.shared.windows.forEach { window in
            if window.isHidden == false && window.windowLevel > topWindow.windowLevel {
                topWindow = window
            }
        }

        //Display touch indicator on screen
        event.allTouches?.forEach { touch in
            let phase = touch.phase
            switch phase {
            case .began:
                guard let view = dequeueTouchView else {
                    return
                }
                view.config = TouchVisualiser.instance.config
                view.touch = touch
                view.touchDidBegin()
                view.center = touch.location(in: topWindow)
                topWindow.addSubview(view)

            case .moved:
                if let view = findTouchView(touch) {
                    view.center = touch.location(in: topWindow)
                }

            case .ended, .cancelled:
                if let view = findTouchView(touch) {
                    UIView.animate(withDuration: 0.2,
                                   delay: 0.0,
                                   options: .allowUserInteraction,
                                   animations: {
                                       view.alpha = 0.0
                                       view.touchDidEnd()
                                   }, completion: { [weak self] _ in
                                       view.removeFromSuperview()
                                       self?.log(touch)
                                   })
                }

            case .stationary, .regionEntered, .regionMoved, .regionExited:
                break

            default:
                break
            }
            log(touch)
        }
    }
}

// MARK: - Logging
extension TouchVisualiser {
    internal func log(_ touch: UITouch) {
        //Check if logging is enabled
        guard config.loggingEnabled else {
            return
        }

        //Construct log of active touches based on phase of touch event
        var touchIndex = 0
        var viewLogs: [[String: String]] = []
        for view in touchViews {
            touchIndex += 1
            let phase: String = String(describing: touch.phase)
            let x = String(format: "%.02f", view.center.x)
            let y = String(format: "%.02f", view.center.y)
            let center = "(\(x), \(y))"
            let radius = String(format: "%.02f", touch.majorRadius)
            viewLogs.append([
                "index": "\(touchIndex)",
                "center": center,
                "phase": phase,
                "radius": radius])
        }

        //Construct single, printable log value for all view logs above.
        var log = ""
        for viewLog in viewLogs {
            guard let index = viewLog["index"], index.count != 0 else {
                continue
            }
            guard let center = viewLog["center"] else {
                continue
            }
            guard let phase = viewLog["phase"] else {
                continue
            }
            guard let radius = viewLog["radius"] else {
                continue
            }
            log += "Touch: [\(index)]<\(phase)> c:\(center) r:\(radius)\t\n"
        }

        //Print constructed log, ensuring that we're not duplicating the last known print.
        if log == previousLog {
            return
        }
        previousLog = log
        logMessage(log)
    }
}
