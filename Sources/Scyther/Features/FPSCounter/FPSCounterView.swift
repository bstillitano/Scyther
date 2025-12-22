//
//  FPSCounterView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 21/12/2024.
//

#if !os(macOS)
import UIKit

/// A view that displays the current FPS (frames per second) as an overlay.
///
/// `FPSCounterView` is a ``TopLevelView`` subclass that shows a floating label
/// with the current frame rate. The label is color-coded to quickly identify
/// performance issues:
/// - **Green**: 55-60+ FPS (excellent)
/// - **Yellow**: 30-54 FPS (acceptable)
/// - **Red**: <30 FPS (poor)
///
/// The view automatically updates its position based on the `FPSCounter.position`
/// setting and avoids the safe area insets to ensure visibility.
///
/// - Note: This is an internal class used by ``InterfaceToolkit``.
internal class FPSCounterView: TopLevelView {
    // MARK: - Constants

    /// Padding from screen edges.
    private static let edgePadding: CGFloat = 8.0

    /// Horizontal padding inside the label.
    private static let labelPaddingH: CGFloat = 8.0

    /// Vertical padding inside the label.
    private static let labelPaddingV: CGFloat = 4.0

    /// Corner radius for the label background.
    private static let cornerRadius: CGFloat = 6.0

    /// Font size for the FPS text.
    private static let fontSize: CGFloat = 12.0

    // MARK: - UI Elements

    /// Background view for the FPS label.
    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.layer.cornerRadius = cornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    /// Label displaying the FPS value.
    private let fpsLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.text = "-- FPS"
        return label
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        isUserInteractionEnabled = false
        isOpaque = false

        addSubview(backgroundView)
        backgroundView.addSubview(fpsLabel)

        updateFrame()
    }

    // MARK: - Frame Updates

    /// Updates the view's frame to match the current screen bounds and position setting.
    internal override func updateFrame() {
        frame = UIScreen.main.bounds
        updatePosition()
    }

    /// Updates the position of the FPS label based on the current setting.
    internal func updatePosition() {
        fpsLabel.sizeToFit()

        let labelWidth = fpsLabel.frame.width + (Self.labelPaddingH * 2)
        let labelHeight = fpsLabel.frame.height + (Self.labelPaddingV * 2)

        // Get safe area insets
        let safeAreaInsets = safeAreaInsetsFromWindow()

        let position = FPSCounter.instance.position
        var x: CGFloat = 0
        var y: CGFloat = 0

        switch position {
        case .topLeft:
            x = Self.edgePadding + safeAreaInsets.left
            y = Self.edgePadding + safeAreaInsets.top
        case .topRight:
            x = bounds.width - labelWidth - Self.edgePadding - safeAreaInsets.right
            y = Self.edgePadding + safeAreaInsets.top
        case .bottomLeft:
            x = Self.edgePadding + safeAreaInsets.left
            y = bounds.height - labelHeight - Self.edgePadding - safeAreaInsets.bottom
        case .bottomRight:
            x = bounds.width - labelWidth - Self.edgePadding - safeAreaInsets.right
            y = bounds.height - labelHeight - Self.edgePadding - safeAreaInsets.bottom
        }

        backgroundView.frame = CGRect(x: x, y: y, width: labelWidth, height: labelHeight)
        fpsLabel.frame = CGRect(
            x: Self.labelPaddingH,
            y: Self.labelPaddingV,
            width: fpsLabel.frame.width,
            height: fpsLabel.frame.height
        )
    }

    /// Gets the safe area insets from the key window.
    private func safeAreaInsetsFromWindow() -> UIEdgeInsets {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .safeAreaInsets ?? .zero
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
        }
    }

    // MARK: - FPS Updates

    /// Updates the displayed FPS value.
    ///
    /// - Parameter fps: The current frames per second.
    internal func updateFPS(_ fps: Int) {
        fpsLabel.text = "\(fps) FPS"
        fpsLabel.textColor = FPSCounter.color(for: fps)
        updatePosition()
    }
}
#endif
