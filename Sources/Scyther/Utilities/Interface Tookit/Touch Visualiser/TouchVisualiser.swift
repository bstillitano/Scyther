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
            print("Scyther.TouchVisualiser: Starting")
        }
        enabled = true
        removeAllTouchViews()
        
        //Log successful startup
        if config.loggingEnabled {
            print("Scyther.TouchVisualiser: Started")
        }
    }

    internal func stop() {
        //Set Data
        if config.loggingEnabled {
            print("Scyther.TouchVisualiser: Stopping")
        }
        enabled = false
        removeAllTouchViews()
        
        //Log successful shutdown
        if config.loggingEnabled {
            print("Scyther.TouchVisualiser: Stopped")
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
}

extension TouchVisualiser {

    // MARK: - Dequeue and locating TouchViews and handling events
    private func dequeueTouchView() -> TouchView {
        var touchView: TouchView?
        for view in touchViews {
            if view.superview == nil {
                touchView = view
                break
            }
        }

        if touchView == nil {
            touchView = TouchView()
            touchViews.append(touchView!)
        }

        return touchView!
    }

    private func findTouchView(_ touch: UITouch) -> TouchView? {
        for view in touchViews {
            if touch == view.touch {
                return view
            }
        }

        return nil
    }

    internal func handleEvent(_ event: UIEvent) {
        if event.type != .touches {
            return
        }

        if !TouchVisualiser.instance.enabled {
            return
        }

        var topWindow = UIApplication.shared.keyWindow!
        for window in UIApplication.shared.windows {
            if window.isHidden == false && window.windowLevel > topWindow.windowLevel {
                topWindow = window
            }
        }

        for touch in event.allTouches! {
            let phase = touch.phase
            switch phase {
            case .began:
                let view = dequeueTouchView()
                view.config = TouchVisualiser.instance.config
                view.touch = touch
                view.beginTouch()
                view.center = touch.location(in: topWindow)
                topWindow.addSubview(view)
            case .moved:
                if let view = findTouchView(touch) {
                    view.center = touch.location(in: topWindow)
                }
            case .ended, .cancelled:
                if let view = findTouchView(touch) {
                    UIView.animate(withDuration: 0.2, delay: 0.0, options: .allowUserInteraction, animations: { () -> Void in
                        view.alpha = 0.0
                        view.endTouch()
                    }, completion: { [unowned self] (finished) -> Void in
                        view.removeFromSuperview()
                        self.log(touch)
                    })
                }
            case .stationary, .regionEntered, .regionMoved, .regionExited:
                break
            @unknown default:
                break
            }
            log(touch)
        }
    }
}

extension TouchVisualiser {
    internal func validateEnvironment() {
        if AppEnvironment.isSimulator {
            print("Scyther.TouchVisualiser: Touch radius doesn't work on the simulator because it is not possible to read touch radius on it.")
        }
    }

    // MARK: - Logging
    internal func log(_ touch: UITouch) {
        if !config.loggingEnabled {
            return
        }

        var ti = 0
        var viewLogs = [[String: String]]()
        for view in touchViews {
            var index = ""

            index = "\(ti)"
            ti += 1

            var phase: String!
            switch touch.phase {
            case .began: phase = "B"
            case .moved: phase = "M"
            case .stationary: phase = "S"
            case .ended: phase = "E"
            case .cancelled: phase = "C"
            case .regionEntered: phase = "REN"
            case .regionMoved: phase = "RM"
            case .regionExited: phase = "REX"
            @unknown default: phase = "U"
            }

            let x = String(format: "%.02f", view.center.x)
            let y = String(format: "%.02f", view.center.y)
            let center = "(\(x), \(y))"
            let radius = String(format: "%.02f", touch.majorRadius)
            viewLogs.append(["index": index, "center": center, "phase": phase, "radius": radius])
        }

        var log = ""

        for viewLog in viewLogs {

            if (viewLog["index"]!).count == 0 {
                continue
            }

            let index = viewLog["index"]!
            let center = viewLog["center"]!
            let phase = viewLog["phase"]!
            let radius = viewLog["radius"]!
            log += "Touch: [\(index)]<\(phase)> c:\(center) r:\(radius)\t\n"
        }

        if log == previousLog {
            return
        }

        previousLog = log
        print(log, terminator: "")
    }
}
