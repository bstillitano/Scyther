//
//  TouchView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

/// A visual indicator that displays touch events on screen.
///
/// `TouchView` is an image view that represents a single touch point. It can optionally
/// display the touch duration and adapt its size based on the touch radius.
///
/// This class is used internally by `TouchVisualiser` to create visual representations
/// of touches on the screen for debugging and demonstration purposes.
@MainActor
final public class TouchView: UIImageView {
    // MARK: - Data
    /// The touch event this view represents.
    internal weak var touch: UITouch?

    /// Timer for updating the touch duration display.
    private weak var timer: Timer!

    /// The previous size ratio used for touch radius visualization.
    private var previousRatio: CGFloat = 1.0

    /// The time when the touch began.
    private var startDate: Date?

    /// The last displayed time string to avoid redundant updates.
    private var lastTimeString: String?

    /// Configuration for this touch view.
    ///
    /// Updating this property refreshes the visual appearance.
    internal var config: TouchVisualiserConfiguration {
        get {
            return configuration
        }
        set {
            configuration = newValue
            image = configuration.touchIndicatorImage
            tintColor = configuration.touchIndicatorColor
            timerLabel.textColor = configuration.touchIndicatorColor
        }
    }
    /// Internal configuration storage.
    private var configuration: TouchVisualiserConfiguration

    // MARK: - UI Elements
    /// Label that displays the touch duration when enabled.
    private lazy var timerLabel: UILabel = {
        let size = CGSize(width: 200.0, height: 44.0)
        let bottom: CGFloat = 8.0
        var label = UILabel()
        label.frame = CGRect(x: -(size.width - self.frame.width) / 2,
                             y: -size.height - bottom,
                             width: size.width,
                             height: size.height)
        label.font = .systemFont(ofSize: 20.0)
        label.textAlignment = .center
        self.addSubview(label)
        return label
    }()

    // MARK: - Lifecycle
    // Note: Timer is weak and will be invalidated when view is deallocated

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        configuration = TouchVisualiserConfiguration()
        super.init(frame: frame)
        self.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: configuration.touchIndicatorSize)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Helper Functions
    /// Called when a touch event begins.
    ///
    /// Initializes the view's appearance and starts the duration timer if enabled.
    internal func touchDidBegin() {
        //Update UI
        alpha = 1.0
        timerLabel.alpha = 0.0
        layer.transform = CATransform3DIdentity
        previousRatio = 1.0
        frame = CGRect(origin: frame.origin, size: configuration.touchIndicatorSize)
        
        //Start Timer
        if configuration.showsTouchDuration {
            startDate = Date()
            timer = Timer.scheduledTimer(timeInterval: 1.0 / 60.0,
                                         target: self,
                                         selector: #selector(self.update(_:)),
                                         userInfo: nil,
                                         repeats: true)
            RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
            timerLabel.alpha = 1.0
        }

        //Show Touch Radius
        if configuration.showsTouchRadius {
            updateSize()
        }
    }

    /// Called when a touch event ends.
    ///
    /// Stops the duration timer.
    func touchDidEnd() {
        timer?.invalidate()
    }

    // MARK: - Update Functions
    /// Updates the duration display for this touch.
    ///
    /// Called repeatedly by the timer while the touch is active.
    ///
    /// - Parameter timer: The timer triggering the update.
    @objc internal func update(_ timer: Timer) {
        guard let startDate = startDate else {
            return
        }
        let interval = Date().timeIntervalSince(startDate)
        let timeString = String(format: "%.02f", Float(interval))
        timerLabel.text = timeString

        //Show Touch Radius
        if configuration.showsTouchRadius {
            updateSize()
        }
    }

    /// Updates the size of the touch indicator based on the touch radius.
    ///
    /// This method scales the view to match the actual touch area. Only has an effect
    /// on physical devices, as simulators don't provide touch radius information.
    internal func updateSize() {
        guard let touch = touch else {
            return
        }
        let ratio = touch.majorRadius * 2.0 / configuration.touchIndicatorSize.width
        if ratio != previousRatio {
            layer.transform = CATransform3DMakeScale(ratio, ratio, 1.0)
            previousRatio = ratio
        }
    }
}
