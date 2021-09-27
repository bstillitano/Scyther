//
//  File.swift
//
//
//  Created by Brandon Stillitano on 26/9/21.
//

import UIKit

final public class TouchView: UIImageView {
    // MARK: - Data
    internal weak var touch: UITouch?
    private weak var timer: Timer!
    private var previousRatio: CGFloat = 1.0
    private var startDate: Date?
    private var lastTimeString: String?
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
    private var configuration: TouchVisualiserConfiguration

    // MARK: - UI Elements
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
    deinit {
        timer?.invalidate()
    }

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

    func touchDidEnd() {
        timer?.invalidate()
    }

    // MARK: - Update Functions
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
