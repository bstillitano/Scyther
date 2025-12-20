//
//  TouchVisualiserConfiguration.swift
//  Scyther
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

/// Configuration options for the touch visualisation feature.
///
/// This structure controls the appearance and behavior of touch indicators displayed
/// on screen when the touch visualiser is enabled.
///
/// ## Usage
/// ```swift
/// var config = TouchVisualiserConfiguration()
/// config.touchIndicatorColor = .red
/// config.showsTouchDuration = true
/// config.showsTouchRadius = true
/// TouchVisualiser.instance.config = config
/// ```
public struct TouchVisualiserConfiguration {
    // MARK: - Data
    /// The color used for touch indicators.
    ///
    /// This color is applied to both the touch indicator circle and the duration label.
    /// Default is semi-transparent gray.
    public var touchIndicatorColor: UIColor = UIColor.systemGray.withAlphaComponent(0.7)

    /// A custom image to use for touch indicators.
    ///
    /// When set to a non-nil value, this image replaces the default color-based circle.
    /// If nil, a colored circle is generated using `touchIndicatorColor` and `touchIndicatorSize`.
    public var touchIndicatorImage: UIImage? {
        get {
            return indicatorImage ?? .touchIndicatorImage(withColor: touchIndicatorColor,
                                                         andSize: touchIndicatorSize)
        }
        set {
            indicatorImage = newValue
        }
    }
    /// Internal storage for custom indicator image.
    private var indicatorImage: UIImage?

    /// The size of touch indicators.
    ///
    /// This value is used as the base size for touch indicators. When `showsTouchRadius`
    /// is enabled, indicators scale relative to this size based on actual touch radius.
    /// Default is 60x60 points.
    internal var touchIndicatorSize = CGSize(width: 60.0, height: 60.0)

    /// Whether to display the duration of each touch.
    ///
    /// When enabled, a label appears above each touch showing how long it has been active.
    /// Useful for debugging time-based interactions like long presses. Default is `false`.
    internal var showsTouchDuration = false

    /// Whether to visualize the radius of each touch.
    ///
    /// When enabled, touch indicators scale to match the actual touch area. This only
    /// works on physical devices, as simulators don't provide touch radius information.
    /// Default is `false`.
    internal var showsTouchRadius = false

    /// Whether to enable console logging of touch events.
    ///
    /// When enabled, detailed touch information is logged to the console. This has a
    /// performance impact and is automatically disabled in App Store builds regardless
    /// of this setting. Default is `false`.
    public var loggingEnabled: Bool {
        get {
            return AppEnvironment.isAppStore ? false : logsEnabled
        }
        set {
            logsEnabled = newValue
        }
    }

    /// Internal storage for logging enabled state.
    private var logsEnabled: Bool = false

    // MARK: - Lifecycle
    /// Creates a new touch visualiser configuration with default values.
    public init() { }
}
