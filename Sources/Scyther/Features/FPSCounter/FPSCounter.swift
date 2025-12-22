//
//  FPSCounter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import UIKit

/// Defines the available positions for the FPS counter overlay.
///
/// Choose a position that doesn't interfere with your app's UI.
public enum FPSCounterPosition: String, CaseIterable, Sendable {
    /// Display in the top-left corner of the screen.
    case topLeft
    /// Display in the top-right corner of the screen.
    case topRight
    /// Display in the bottom-left corner of the screen.
    case bottomLeft
    /// Display in the bottom-right corner of the screen.
    case bottomRight

    /// Human-readable display name for the position.
    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// A singleton manager for displaying a real-time FPS (frames per second) counter overlay.
///
/// `FPSCounter` uses `CADisplayLink` to measure the actual frame rate of your app's
/// rendering and displays it as a floating overlay. The counter is color-coded to
/// quickly identify performance issues:
/// - **Green** (55-60+ FPS): Excellent performance
/// - **Yellow** (30-54 FPS): Acceptable but may need optimization
/// - **Red** (<30 FPS): Poor performance, needs investigation
///
/// Settings are persisted to `UserDefaults` and automatically restored on app launch.
///
/// ```swift
/// // Enable the FPS counter
/// FPSCounter.instance.enabled = true
///
/// // Change position
/// FPSCounter.instance.position = .bottomRight
/// ```
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
///
/// ### Configuration
/// - ``enabled``
/// - ``position``
///
/// ### Reading FPS Data
/// - ``currentFPS``
@MainActor
public final class FPSCounter: Sendable {
    // MARK: - Static Data (nonisolated for cross-thread access)

    /// UserDefaults key for storing the FPS counter enabled state.
    nonisolated static let EnabledDefaultsKey: String = "Scyther_fps_counter_enabled"

    /// UserDefaults key for storing the FPS counter position.
    nonisolated static let PositionDefaultsKey: String = "Scyther_fps_counter_position"

    /// Private init to stop re-initialisation and allow singleton creation.
    private init() { }

    /// The shared singleton instance of `FPSCounter`.
    ///
    /// Use this instance to access all FPS counter functionality.
    public static let instance = FPSCounter()

    // MARK: - Display Link

    /// The display link used to measure frame rate.
    private var displayLink: CADisplayLink?

    /// Timestamp of the last frame rate calculation.
    private var lastTimestamp: CFTimeInterval = 0

    /// Number of frames counted in the current measurement window.
    private var frameCount: Int = 0

    /// The current measured frames per second.
    ///
    /// This value is updated approximately once per second and reflects the
    /// actual rendering performance of the app.
    public private(set) var currentFPS: Int = 0

    // MARK: - Configuration

    /// Controls whether the FPS counter overlay is visible on screen.
    ///
    /// Setting this to `true` displays the FPS counter and starts measuring frame rate.
    /// The value is persisted to UserDefaults and restored on app launch.
    public nonisolated var enabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: FPSCounter.EnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: FPSCounter.EnabledDefaultsKey)
            Task { @MainActor in
                if newValue {
                    self.start()
                } else {
                    self.stop()
                }
                InterfaceToolkit.instance.showFPSCounter()
            }
        }
    }

    /// The position of the FPS counter on screen.
    ///
    /// Choose a corner that doesn't interfere with your app's UI.
    /// The value is persisted to UserDefaults.
    public nonisolated var position: FPSCounterPosition {
        get {
            let rawValue = UserDefaults.standard.string(forKey: FPSCounter.PositionDefaultsKey) ?? "topLeft"
            return FPSCounterPosition(rawValue: rawValue) ?? .topLeft
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: FPSCounter.PositionDefaultsKey)
            Task { @MainActor in
                InterfaceToolkit.instance.fpsCounterView.updatePosition()
            }
        }
    }

    // MARK: - Lifecycle

    /// Starts the FPS counter measurement.
    ///
    /// This method is called automatically when `enabled` is set to `true`.
    /// It creates a `CADisplayLink` to measure frame rate.
    internal func start() {
        guard displayLink == nil else { return }

        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
        lastTimestamp = 0
        frameCount = 0
    }

    /// Stops the FPS counter measurement.
    ///
    /// This method is called automatically when `enabled` is set to `false`.
    /// It invalidates the display link to avoid unnecessary CPU usage.
    internal func stop() {
        displayLink?.invalidate()
        displayLink = nil
        currentFPS = 0
    }

    /// Called on each frame by the display link.
    ///
    /// Counts frames and calculates FPS approximately once per second.
    @objc private func tick(_ link: CADisplayLink) {
        frameCount += 1

        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        let elapsed = link.timestamp - lastTimestamp

        if elapsed >= 1.0 {
            currentFPS = Int(Double(frameCount) / elapsed)
            frameCount = 0
            lastTimestamp = link.timestamp

            // Update the view
            InterfaceToolkit.instance.fpsCounterView.updateFPS(currentFPS)
        }
    }

    // MARK: - FPS Color

    /// Returns the appropriate color for the given FPS value.
    ///
    /// - Parameter fps: The frames per second value.
    /// - Returns: Green for 55+, yellow for 30-54, red for <30.
    public static func color(for fps: Int) -> UIColor {
        switch fps {
        case 55...:
            return .systemGreen
        case 30..<55:
            return .systemYellow
        default:
            return .systemRed
        }
    }
}
#endif
