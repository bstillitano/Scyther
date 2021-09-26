//
//  File.swift
//
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

/// Data struct used to configure the Scyther touch visualisation feature
public struct TouchVisualiserConfiguration {
    // MARK: - Data
    /// Color to be used for touch indicators
    public var touchIndicatorColor: UIColor = .systemGreen

    /// Image to be used for touch indicators. If not nil, this will replace color based touch indicators.
    public var touchIndicatorImage: UIImage? = nil

    /// Touch indicator size. If `showsTouchRadius` is enabled, this value is ignored
    public var touchIndicatorSize = CGSize(width: 60.0, height: 60.0)

    /// Boolean value indicating whether or not the duration of a touch should be shown. Useful when trying to debug time based interactions like press and hold of a `UIButton`. Defaults to `false`.
    public var showsTimer = false

    /// Boolean value indicating the radius of a given touch. This only works on physical devices as touch radius is not supported on simulator given that there is no physical screen to touch.
    public var showsTouchRadius = false

    /// Boolean value indicating whether or not logging should be enabled for touches. This has a drastic impact on performance, so will always be disabled when running within an AppStore environment, even if set to true.
    public var loggingEnabled: Bool {
        get {
            return AppEnvironment.isAppStore ? false : logsEnabled
        }
        set {
            logsEnabled = newValue
        }
    }
    private var logsEnabled: Bool = false

    // MARK: - Lifecycle
    public init() { }
}
