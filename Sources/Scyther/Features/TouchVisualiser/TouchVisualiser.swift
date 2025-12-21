//
//  TouchVisualiser.swift
//  Scyther
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

/// A singleton that visualizes touch events on screen for debugging and demonstration.
///
/// `TouchVisualiser` intercepts touch events and displays visual indicators showing where
/// touches occur, optionally including duration and radius information. This is useful for:
/// - Debugging touch interactions
/// - Creating app demos and tutorials
/// - Testing touch-based gestures
///
/// ## Usage
/// ```swift
/// // Start visualizing touches
/// TouchVisualiser.instance.start()
///
/// // Configure appearance
/// var config = TouchVisualiserConfiguration()
/// config.showsTouchDuration = true
/// config.touchIndicatorColor = .red
/// TouchVisualiser.instance.config = config
///
/// // Stop visualizing
/// TouchVisualiser.instance.stop()
/// ```
@MainActor
public final class TouchVisualiser: NSObject, Sendable {
    // MARK: - Data
    /// Static flag for hot path access without MainActor hop
    nonisolated(unsafe) internal static var isEnabled = false

    /// Whether touch visualization is currently enabled.
    private(set) var enabled: Bool {
        get { Self.isEnabled }
        set { Self.isEnabled = newValue }
    }

    /// Configuration controlling the appearance and behavior of touch indicators.
    public var config: TouchVisualiserConfiguration = TouchVisualiserConfiguration()

    /// Reusable touch view instances for displaying touch indicators.
    private var touchViews: [TouchView] = []

    /// The last logged touch information to prevent duplicate logs.
    private var previousLog = ""

    // MARK: - Lifecycle
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Singleton
    /// Shared singleton instance.
    internal static let instance = TouchVisualiser()

    /// Private initializer to enforce singleton pattern.
    private override init() {
        super.init()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        validateEnvironment()
    }

    // MARK: - Functions
    /// Starts visualizing touches on screen.
    ///
    /// Call this method to begin displaying visual indicators for all touch events.
    /// Removes any existing touch views before starting.
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

    /// Stops visualizing touches on screen.
    ///
    /// Call this method to hide all touch indicators and stop tracking touch events.
    /// Removes all existing touch views from the screen.
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
    /// Removes all touch view indicators from the screen.
    internal func removeAllTouchViews() {
        for view in self.touchViews {
            view.removeFromSuperview()
        }
        if let window = Self.keyWindow {
            for subview in window.subviews {
                if let subview = subview as? TouchView {
                    subview.removeFromSuperview()
                }
            }
        }
    }

    /// The current key window.
    ///
    /// - Returns: The key window, or `nil` if none exists.
    private static var keyWindow: UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }

    /// All windows in the application.
    ///
    /// - Returns: An array of all windows across all window scenes.
    private static var allWindows: [UIWindow] {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
        } else {
            return UIApplication.shared.windows
        }
    }

    /// Validates that the current environment supports all features.
    ///
    /// Logs a warning if running on simulator, as touch radius is not available.
    internal func validateEnvironment() {
        if AppEnvironment.isSimulator {
            logMessage("TouchVisualiser: Touch radius doesn't work on the simulator because it is not possible to read touch radius on it.")
        }
    }
}

// MARK: - Touch view recycling
extension TouchVisualiser {
    /// Dequeues a reusable touch view or creates a new one if none are available.
    ///
    /// This method implements view recycling to minimize allocations during active touch tracking.
    ///
    /// - Returns: A touch view ready to display a new touch, or `nil` if creation fails.
    private var dequeueTouchView: TouchView? {
        var touchView: TouchView? = touchViews.first(where: { $0.superview == nil })
        if touchView == nil {
            touchView = TouchView()
            touchViews.append(touchView ?? TouchView())
        }
        return touchView
    }

    /// Finds the touch view associated with a specific touch event.
    ///
    /// - Parameter touch: The touch event to find a view for.
    /// - Returns: The touch view displaying this touch, or `nil` if not found.
    private func findTouchView(_ touch: UITouch) -> TouchView? {
        return touchViews.first(where: { touch == $0.touch })
    }

    /// Handles a touch event by displaying or updating visual indicators.
    ///
    /// This method is called for each touch event and manages the lifecycle of touch views,
    /// creating them for new touches, updating them as touches move, and removing them
    /// when touches end.
    ///
    /// - Parameter event: The touch event to handle.
    internal func handleEvent(_ event: UIEvent) {
        //Determine whether or not the event should be handled by Scyther.
        guard enabled && event.type == .touches else {
            return
        }

        //Get top most key window
        guard var topWindow = Self.keyWindow else {
            return
        }
        Self.allWindows.forEach { window in
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
                view.config = self.config
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
    /// Logs detailed information about a touch event.
    ///
    /// When logging is enabled, this method outputs touch details including position,
    /// phase, and radius to the console. Duplicate logs are suppressed.
    ///
    /// - Parameter touch: The touch to log information about.
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
