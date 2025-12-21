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
            // Note: timerLabel uses its own fixed styling (white text on dark background)
        }
    }
    /// Internal configuration storage.
    private var configuration: TouchVisualiserConfiguration

    // MARK: - UI Elements
    /// Label that displays the touch duration when enabled.
    private lazy var timerLabel: UILabel = {
        let size = CGSize(width: 100.0, height: 32.0)
        let bottom: CGFloat = 8.0
        var label = UILabel()
        label.frame = CGRect(x: -(size.width - self.frame.width) / 2,
                             y: -size.height - bottom,
                             width: size.width,
                             height: size.height)
        label.font = .monospacedDigitSystemFont(ofSize: 17.0, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textColor = .white
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
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
        clipsToBounds = false  // Must set every time since views are reused and setting image resets this
        timerLabel.alpha = 0.0
        layer.transform = CATransform3DIdentity
        previousRatio = 1.0
        frame = CGRect(origin: frame.origin, size: configuration.touchIndicatorSize)

        // Update timerLabel frame in case view frame changed
        updateTimerLabelFrame()

        //Start Timer
        if configuration.showsTouchDuration {
            startDate = Date()
            timerLabel.text = "0.00"
            timerLabel.alpha = 1.0
            timerLabel.isHidden = false
            bringSubviewToFront(timerLabel)

            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                MainActor.assumeIsolated {
                    self.updateDuration()
                }
            }
            RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
        }

        //Show Touch Radius
        if configuration.showsTouchRadius {
            updateSize()
        }
    }

    /// Updates the timer label frame to be positioned above the touch indicator.
    private func updateTimerLabelFrame() {
        let size = CGSize(width: 100.0, height: 32.0)
        let bottom: CGFloat = 8.0
        timerLabel.frame = CGRect(
            x: -(size.width - frame.width) / 2,
            y: -size.height - bottom,
            width: size.width,
            height: size.height
        )
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
    private func updateDuration() {
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
