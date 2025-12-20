//
//  UIWindow+Extensions.swift
//
//
//  Created by Brandon Stillitano on 22/12/20.
//

#if os(iOS)
import UIKit

/// Type alias for UIEvent.EventSubtype for convenience.
public typealias UIEventSubtype = UIEvent.EventSubtype

/// Provides extensions to UIWindow for handling device motion events.
///
/// This extension overrides motion detection to enable shake gesture recognition
/// for invoking the Scyther debug menu when configured to use shake gestures.
extension UIWindow {
    /// Handles the end of a motion event, specifically detecting shake gestures.
    ///
    /// This override intercepts motion events and checks if the Scyther debug menu
    /// is configured to be invoked via shake gesture. If so, it displays the menu
    /// when a shake is detected. Otherwise, it passes the event to the superclass.
    ///
    /// - Parameters:
    ///   - motion: The type of motion event that ended
    ///   - event: The event object containing details about the motion
    ///
    /// ## Usage
    /// This method is called automatically by the system when a motion event (like shake)
    /// ends. You don't need to call it directly. The Scyther framework uses this to
    /// detect shake gestures for invoking the debug menu.
    ///
    /// ## Example Configuration
    /// ```swift
    /// // Configure Scyther to use shake gesture
    /// Scyther.invocationGesture = .shake
    ///
    /// // Now shaking the device will invoke the Scyther menu
    /// ```
    ///
    /// - Note: This override only intercepts shake gestures when `Scyther.invocationGesture`
    ///         is set to `.shake`. Other gestures are handled normally.
    ///
    /// - Important: Force unwrapping the event is used here because the method is only
    ///              called by the system with a valid event object.
    override open func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?) {
        if Scyther.invocationGesture == .shake {
            if (event!.type == .motion && event!.subtype == .motionShake) {
                Scyther.showMenu()
            }
        } else {
            super.motionEnded(motion, with: event)
        }
    }
}
#endif
