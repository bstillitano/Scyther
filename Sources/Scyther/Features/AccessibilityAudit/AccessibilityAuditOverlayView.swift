//
//  AccessibilityAuditOverlayView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

#if !os(macOS)
import UIKit

/// Where a finding's box is stroked, and how strongly it reads as a problem.
///
/// This lives here rather than on ``AccessibilitySeverity`` itself because the severity model
/// is deliberately UIKit-free — every rule in ``AccessibilityAuditor`` is testable against plain
/// values — and a `UIColor` is exactly the kind of UIKit dependency that split was meant to keep
/// out of it.
private extension AccessibilitySeverity {
    /// The stroke colour a box or a flash animation draws in, matching how the rest of Scyther's
    /// UI already reads these two levels: red for something broken for somebody, amber for
    /// something worth a look that might be deliberate.
    var overlayStrokeColor: UIColor {
        switch self {
        case .error: return .systemRed
        case .warning: return .systemOrange
        }
    }
}

/// Draws the accessibility audit's findings over the running app.
///
/// `AccessibilityAuditOverlayView` is a ``TopLevelView`` — the same base ``GridOverlayView`` and
/// ``FPSCounterView`` use — so ``InterfaceToolkit`` can keep it above the app's own content
/// through ``TopLevelViewsWrapper`` without this view knowing anything about how that is
/// arranged. It has exactly one interactive element, the pill at the bottom centre reporting how
/// many findings there are; everything else — the boxes ``draw(_:)`` strokes around each finding
/// — is drawn, not a view, so there is nothing there for a touch to land on in the first place.
///
/// ## Not swallowing the app's touches
///
/// The view fills the superview's bounds (see ``updateFrame()``), which means a naïve
/// `isUserInteractionEnabled = true` would make it — not the app underneath — the thing every
/// touch on screen hits first, defeating the entire point of a debugging overlay: the developer
/// needs to keep scrolling, tapping and typing in the app while findings are on screen. Instead
/// ``point(inside:with:)`` is overridden to report `true` only inside ``reportButton``'s own
/// frame. `UIKit`'s hit-testing checks that method *before* it ever considers a view's subviews,
/// so everywhere else on screen this view reports "the touch isn't inside me" and
/// ``TopLevelViewsWrapper``'s own hit-testing — which already skips any subview whose `hitTest`
/// comes back `nil` — lets the touch fall straight through to whatever the app has underneath.
/// Only a touch that actually lands on the pill reaches this view, and from there `UIButton`'s
/// own hit-testing hands it to ``reportButton``.
internal class AccessibilityAuditOverlayView: TopLevelView {
    // MARK: - Static Data

    /// Width of the stroke drawn around each finding's frame.
    private static let strokeWidth: CGFloat = 2

    /// Corner radius of the stroke drawn around each finding's frame.
    private static let strokeCornerRadius: CGFloat = 4

    /// Gap between the pill and the bottom of the safe area.
    private static let pillBottomPadding: CGFloat = 24

    /// How long one on/off cycle of ``flash(_:)``'s animation takes. Two cycles at this duration
    /// makes the full flash 0.6 seconds, matching the rest of Scyther's brief, noticeable
    /// animations.
    private static let flashCycleDuration: TimeInterval = 0.15

    // MARK: - UI Elements

    /// The tappable pill at the bottom centre of the screen reporting how many findings there
    /// are. A real `UIButton` rather than a drawn shape, because a drawn shape cannot receive
    /// touches — see the type-level discussion of how this view avoids swallowing the app's own
    /// touches everywhere *except* here.
    private let reportButton = UIButton()

    // MARK: - Data

    /// The findings currently on screen.
    ///
    /// Setting this redraws the boxes and refreshes the pill's count in one step, so a caller —
    /// ``InterfaceToolkit/scheduleAccessibilityReaudit()`` after a fresh audit — only has to
    /// assign the new array and never has to remember to ask for a redraw itself.
    internal var findings: [AccessibilityFinding] = [] {
        didSet {
            setNeedsDisplay()
            updateReportButton()
        }
    }

    /// Called when the pill is tapped.
    ///
    /// Left unset by ``InterfaceToolkit``'s setup in this task: there is no report screen yet
    /// for the pill to open one of. A later task assigns this once that screen exists, at which
    /// point tapping the pill starts working with no further change needed here.
    internal var onOpenReport: (() -> Void)?

    /// Called at the end of every ``updateFrame()``.
    ///
    /// `updateFrame()` runs whenever the overlay's size might have changed — initial setup, a
    /// rotation — which is also exactly when the app's own layout might have changed underneath
    /// it. ``InterfaceToolkit`` uses this hook to debounce a fresh audit rather than this view
    /// reaching into `InterfaceToolkit` itself, keeping the direction of dependency the same way
    /// round as the rest of Scyther's overlays: `InterfaceToolkit` configures its views, not the
    /// other way around.
    internal var onFrameChanged: (() -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures the view and its one subview.
    ///
    /// Unlike ``GridOverlayView`` and ``FPSCounterView``, this view does not disable
    /// `isUserInteractionEnabled` on itself — doing so would stop `UIKit` from ever hit-testing
    /// ``reportButton``, since a view with interaction disabled is skipped before its subviews
    /// are even considered. ``point(inside:with:)`` does the same job more precisely, letting
    /// through everything except the pill itself.
    private func setupUI() {
        isOpaque = false
        backgroundColor = .clear

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.85)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .semibold)
            return outgoing
        }
        reportButton.configuration = configuration
        reportButton.isHidden = true
        reportButton.addTarget(self, action: #selector(reportButtonTapped), for: .touchUpInside)
        addSubview(reportButton)

        updateFrame()
    }

    // MARK: - Frame Updates

    /// Matches this view to whatever it is sitting inside — `TopLevelViewsWrapper`, which is
    /// itself kept sized to the screen — rather than reading `UIScreen.main.bounds` directly the
    /// way the older overlays in this file's neighbours do; both arrive at the same rectangle in
    /// practice, but going through the actual superview is one fewer assumption about how this
    /// view happens to be hosted.
    internal override func updateFrame() {
        frame = superview?.bounds ?? UIScreen.main.bounds
        layoutReportButton()
        onFrameChanged?()
    }

    /// Centres ``reportButton`` at the bottom of the screen, clear of the home indicator.
    private func layoutReportButton() {
        reportButton.sizeToFit()
        let bottomInset = window?.safeAreaInsets.bottom ?? 0
        let size = reportButton.frame.size
        reportButton.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - bottomInset - Self.pillBottomPadding - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Report Button

    /// Shows or hides the pill and refreshes its count.
    ///
    /// Hiding it — rather than leaving it visible reading "0 issues" — is what lets
    /// ``point(inside:with:)`` stay a single frame check: a hidden button's frame is never where
    /// this view reports a touch as landing, because the guard below checks `isHidden` first.
    private func updateReportButton() {
        let count = findings.count
        reportButton.isHidden = count == 0
        guard count > 0 else { return }

        let title = localized("\(count) issues")
        reportButton.configuration?.title = title
        reportButton.accessibilityLabel = title
        layoutReportButton()
    }

    /// Forwards a tap on the pill to ``onOpenReport``.
    @objc
    private func reportButtonTapped() {
        onOpenReport?()
    }

    // MARK: - Hit Testing

    /// Reports this view as containing only the point directly over ``reportButton``.
    ///
    /// See the type-level documentation for why this, rather than disabling
    /// `isUserInteractionEnabled`, is what keeps every touch other than a tap on the pill
    /// reaching the app underneath.
    ///
    /// - Parameters:
    ///   - point: The point to test, in this view's own coordinate space.
    ///   - event: The event the point came from. Unused: the pill's frame is all that matters.
    /// - Returns: `true` only when the pill is visible and `point` falls inside it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !reportButton.isHidden && reportButton.frame.contains(point)
    }

    // MARK: - Drawing

    /// Strokes one rounded rectangle per finding.
    ///
    /// - Parameter rect: The portion of the view's bounds that needs to be redrawn.
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for finding in findings {
            context.setStrokeColor(finding.severity.overlayStrokeColor.cgColor)
            context.setLineWidth(Self.strokeWidth)
            let path = UIBezierPath(roundedRect: finding.frame, cornerRadius: Self.strokeCornerRadius)
            context.addPath(path.cgPath)
            context.strokePath()
        }
    }

    // MARK: - Flashing a Finding

    /// Draws attention to one finding by flashing its box to full opacity and back, twice, over
    /// 0.6 seconds.
    ///
    /// The flash is a temporary `CAShapeLayer` rather than a property this view's own
    /// `draw(_:)` reads, because Core Graphics drawing has no notion of an in-flight animation —
    /// `draw(_:)` renders one static frame per call. A layer, by contrast, is exactly the kind of
    /// object `Core Animation` knows how to animate on its own, so the flash costs nothing beyond
    /// adding and, once it finishes, removing one layer.
    ///
    /// - Parameter finding: The finding whose box should flash. Its own severity colour is used,
    ///   matching the box ``draw(_:)`` already drew for it.
    internal func flash(_ finding: AccessibilityFinding) {
        let path = UIBezierPath(roundedRect: finding.frame, cornerRadius: Self.strokeCornerRadius)
        let flashLayer = CAShapeLayer()
        flashLayer.path = path.cgPath
        flashLayer.fillColor = UIColor.clear.cgColor
        flashLayer.strokeColor = finding.severity.overlayStrokeColor.cgColor
        flashLayer.lineWidth = Self.strokeWidth
        flashLayer.opacity = 1
        layer.addSublayer(flashLayer)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.25
        animation.toValue = 1.0
        animation.duration = Self.flashCycleDuration
        animation.autoreverses = true
        animation.repeatCount = 2
        flashLayer.add(animation, forKey: "flash")

        let totalDuration = Self.flashCycleDuration * Double(animation.repeatCount) * 2
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak flashLayer] in
            flashLayer?.removeFromSuperlayer()
        }
    }
}
#endif
