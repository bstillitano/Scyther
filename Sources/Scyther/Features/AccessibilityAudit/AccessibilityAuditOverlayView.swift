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
/// arranged. It has exactly one interactive element, the pill down the trailing edge reporting how
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

    /// Gap between the pill and the trailing edge of the safe area.
    ///
    /// The pill used to sit at the bottom centre, which is the one band of the screen an app is
    /// most likely to have already claimed: a `UITabBar` is 49pt tall plus the home indicator's
    /// safe area and spans the full width, and a bottom primary action button occupies the same
    /// place on a screen that has no tab bar. This is the only interactive region Scyther has ever
    /// installed over the running app — ``GridOverlayView`` and ``FPSCounterView`` both switch
    /// interaction off entirely — so a pill there does not merely overlap the app's controls, it
    /// takes their taps. The trailing edge at the vertical midpoint is the emptiest band left: the
    /// bars run along the top and bottom, and the only thing living down the side of a screen is a
    /// scroll indicator, which is not interactive.
    private static let pillTrailingPadding: CGFloat = 16

    /// How long one on/off cycle of ``flash(_:)``'s animation takes. Two cycles at this duration
    /// makes the full flash 0.6 seconds, matching the rest of Scyther's brief, noticeable
    /// animations.
    private static let flashCycleDuration: TimeInterval = 0.15

    // MARK: - UI Elements

    /// The tappable pill down the trailing edge of the screen reporting how many findings there
    /// are. A real `UIButton` rather than a drawn shape, because a drawn shape cannot receive
    /// touches — see the type-level discussion of how this view avoids swallowing the app's own
    /// touches everywhere *except* here.
    ///
    /// - Note: Readable rather than private so a test can check that the pill is laid out wide
    ///   enough to draw its own title on one line. It is still owned entirely by this view:
    ///   nothing outside may replace it.
    internal private(set) var reportButton = UIButton()

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
            reconcileFlash()
        }
    }

    /// The flash animation currently on screen, if any.
    ///
    /// Held so a second flash can replace the first rather than stack on top of it, and so a pass
    /// that replaces ``findings`` can move it to where the element is now — or take it away when
    /// the element is gone. Nothing used to own it, so a flash outlived the finding it described
    /// and went on stroking a rectangle nothing occupied for the rest of its 0.6 seconds.
    private var flashLayer: CAShapeLayer?

    /// Which finding ``flashLayer`` is describing, so a new pass can be asked whether that element
    /// is still there and still in the same place.
    private var flashedFinding: AccessibilityFinding?

    /// How many flashes have been started, so the delayed removal of one flash cannot take a
    /// later one away with it.
    ///
    /// A counter rather than a captured reference to the layer: the removal is scheduled on the
    /// main queue with `asyncAfter`, which cannot be cancelled, so the block has to be able to
    /// recognise that it is no longer the current flash.
    private var flashGeneration = 0

    /// A flash asked for while Scyther's own UI was in front of the app, kept until it is not.
    ///
    /// Every production flash arrives in exactly this state — the only way to ask for one is to tap
    /// a row in the report, and the report is always covering the app — so refusing outright would
    /// make a deliberate tap do nothing, ever. Holding it until Scyther's screen goes away is what
    /// makes the tap mean something: the box the developer asked about flashes on the app itself,
    /// which is the only place it describes anything.
    private var deferredFlash: AccessibilityFinding?

    /// Called when the pill is tapped.
    ///
    /// Assigned by `InterfaceToolkit.setupAccessibilityAudit()` to
    /// ``AccessibilityAuditReportPresenter/openReport()``, so this view never has to know that
    /// there is a report, where it comes from, or how it reaches the screen — only that its pill
    /// was tapped. Left optional so an overlay created outside that setup (a test, a preview) is
    /// inert rather than reaching for a presenter that is not there.
    internal var onOpenReport: (() -> Void)?

    /// Answers whether Scyther's own UI is covering the app right now.
    ///
    /// Injected rather than read inline so a test can drive both answers without a window, a
    /// presented controller and a presentation animation — none of which would make the drawing
    /// decision any more real. Defaults to ``ScytherPresentation/isCoveringScreen``, deliberately
    /// the *same* answer the contrast check already skips itself on: there is one question here —
    /// "is Scyther in front of the app?" — and two independent answers to it would eventually
    /// disagree.
    internal var isCoveredByScyther: @MainActor () -> Bool = { ScytherPresentation.isCoveringScreen }

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
        // A pill is one line by definition. Left at the default the title wraps the moment the
        // button is ever measured against a width narrower than the title needs — which is
        // exactly what happened, reading "2 issue" over "s" — and a count broken across two lines
        // is unreadable at this size. `.byClipping` makes wrapping impossible, so a mis-measured
        // width would show as a clipped pill rather than a garbled one; ``layoutReportButton()``
        // then makes sure it is never mis-measured in the first place.
        configuration.titleLineBreakMode = .byClipping
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
    ///
    /// Asks for a redraw as well, exactly as ``GridOverlayView/updateFrame()`` does. A `UIView`'s
    /// default `contentMode` is `.scaleToFill`, so changing the bounds without asking for a fresh
    /// `draw(_:)` stretches the last-rendered content into the new shape: every box drawn in
    /// portrait was smeared into the landscape aspect ratio, offset from the element it described,
    /// for at least the length of the re-audit's debounce — and for good if that work item was
    /// cancelled before it fired.
    internal override func updateFrame() {
        frame = superview?.bounds ?? UIScreen.main.bounds
        layoutReportButton()
        setNeedsDisplay()
        onFrameChanged?()
    }

    /// The part of this view the app under audit actually occupies.
    ///
    /// This view is sized to its superview, ``TopLevelViewsWrapper``, which sizes itself to
    /// `UIScreen.main.bounds` — the whole display. In iPad Split View or Slide Over the app's
    /// window is a fraction of that, so laying the pill out against `bounds` puts it beside the app
    /// or off it entirely. Everything else this view draws is a finding's own window-coordinate
    /// frame and lands correctly regardless; the pill is the one thing positioned relative to an
    /// edge, and the edge that matters is the window's.
    private var appArea: CGRect {
        guard let window else { return bounds }
        let area = convert(window.bounds, from: window).intersection(bounds)
        return area.isNull || area.isEmpty ? bounds : area
    }

    /// Puts ``reportButton`` against the trailing edge, halfway down the app's own window.
    ///
    /// See ``pillTrailingPadding`` for why not the bottom centre, where it used to be and where it
    /// overlapped the example app's tab bar.
    ///
    /// Deliberately not `sizeToFit()`, which is what used to draw the pill's title across two
    /// lines. `sizeToFit()` asks the button to fit its *current* bounds, and those bounds are
    /// whatever the previous — shorter, or empty — title left behind, so the button answers with
    /// the size of a wrapped title and is then laid out at exactly that too-narrow width. Asking
    /// for the size that fits the full width of the overlay instead gives the title all the room
    /// there is, and the answer is the natural single-line width of the pill.
    ///
    /// The layout pass before it is what makes that answer describe the title the pill is about to
    /// show: a `UIButton.Configuration` is applied on the button's next update pass, so until one
    /// has run the button is still measuring the title it had last time.
    private func layoutReportButton() {
        reportButton.setNeedsLayout()
        reportButton.layoutIfNeeded()

        let area = appArea
        let available = CGSize(width: max(area.width, 1), height: .greatestFiniteMagnitude)
        let size = reportButton.sizeThatFits(available)
        let trailingInset = window?.safeAreaInsets.right ?? 0
        reportButton.frame = CGRect(
            x: area.maxX - trailingInset - Self.pillTrailingPadding - size.width,
            y: area.midY - (size.height / 2),
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
    /// The same hiding covers the second reason there should be no pill: Scyther is in front of
    /// the app, so the pill would sit over Scyther's own screen and, being the one part of this
    /// view that takes touches, would steal them from it.
    private func updateReportButton() {
        let count = findings.count
        reportButton.isHidden = count == 0 || isCoveredByScyther()
        guard !reportButton.isHidden else { return }

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

    /// Re-reads ``isCoveredByScyther`` and brings the pill and the boxes back into line with it.
    ///
    /// Called by ``InterfaceToolkit`` when ``ScytherPresentation/coverageDidChangeNotification``
    /// arrives. Nothing else would: a modal appearing over the app changes no frame this view owns
    /// and triggers no redraw of it, so without an explicit nudge the boxes drawn for the app would
    /// simply stay on screen underneath Scyther — and, worse, stay gone after Scyther's screen was
    /// dismissed. Recomputing rather than being handed a boolean is what makes it correct when two
    /// Scyther screens are stacked and only the upper one goes away.
    internal func refreshForCoverageChange() {
        updateReportButton()
        setNeedsDisplay()

        guard !isCoveredByScyther() else {
            // A flash is a box, and a box drawn while Scyther is in front of the app is drawn on
            // Scyther, describing something the developer cannot see. Same rule as `draw(_:)`.
            removeFlash()
            return
        }
        guard let deferred = deferredFlash else { return }
        deferredFlash = nil
        play(deferred)
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
    /// Draws nothing at all while Scyther's own UI is in front of the app. This view is kept above
    /// everything in the key window — ``InterfaceToolkit`` brings ``TopLevelViewsWrapper`` back to
    /// the front whenever the window's layers change — so a modal Scyther presents goes *under* it
    /// and the boxes end up stroked across Scyther's own menu, and across the report the developer
    /// just opened to read them. Every box describes an element of the app underneath, so over
    /// Scyther's UI it is not merely untidy but wrong: it points at a rectangle where nothing it
    /// describes is any longer on screen. Live mode stays on throughout; only the drawing stops,
    /// and it comes straight back when Scyther's screen goes away.
    ///
    /// - Parameter rect: The portion of the view's bounds that needs to be redrawn.
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard !isCoveredByScyther() else { return }
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
    /// Two things stop a flash happening as asked, and both used to be missing.
    ///
    /// It honours the same coverage rule ``draw(_:)`` does. `draw(_:)` refuses to stroke a box
    /// while Scyther is in front of the app, because such a box lands on Scyther's own screen and
    /// points at a rectangle nothing it describes occupies any more; a flash is the same box drawn
    /// through `Core Animation` instead of `Core Graphics`, and used to slip past that rule
    /// entirely — over the very report the developer tapped in. It is held until Scyther's screen
    /// goes away rather than dropped; see ``deferredFlash``.
    ///
    /// And it flashes where the element is *now*, not where the report says it was. The report is
    /// frozen by design, so the finding handed in here can be several passes old and its frame can
    /// describe a screen that has since scrolled, rotated or been navigated away from. A finding
    /// with no counterpart in the current ``findings`` is not flashed at all: a box at a coordinate
    /// nothing occupies is worse than no box.
    ///
    /// - Parameter finding: The finding whose box should flash. Its own severity colour is used,
    ///   matching the box ``draw(_:)`` already drew for it.
    internal func flash(_ finding: AccessibilityFinding) {
        guard !isCoveredByScyther() else {
            deferredFlash = finding
            return
        }
        play(finding)
    }

    /// The finding in the current ``findings`` describing the same element as `finding`, if it is
    /// still there.
    ///
    /// Identity first, for a finding that came from the very pass the overlay is drawing. Failing
    /// that, the check and the element's name: every ``AccessibilityFinding`` is created with a
    /// fresh `UUID`, so a finding read from the report's own pass can never be identical to the
    /// live pass's finding about the same button, and matching on identity alone would mean no
    /// report row ever flashed anything.
    ///
    /// - Parameter finding: The finding to look for, usually a frozen one from the report.
    /// - Returns: The current finding about that element, or `nil` when it is gone.
    private func currentFinding(matching finding: AccessibilityFinding) -> AccessibilityFinding? {
        findings.first { $0.id == finding.id }
            ?? findings.first { $0.check == finding.check && $0.elementName == finding.elementName }
    }

    /// Flashes `finding`'s box to full opacity and back, twice, over 0.6 seconds — if the element
    /// it describes is still on screen.
    ///
    /// - Parameter finding: The finding to flash.
    private func play(_ finding: AccessibilityFinding) {
        guard let current = currentFinding(matching: finding) else { return }

        removeFlash()
        let shape = CAShapeLayer()
        shape.path = UIBezierPath(roundedRect: current.frame, cornerRadius: Self.strokeCornerRadius).cgPath
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = current.severity.overlayStrokeColor.cgColor
        shape.lineWidth = Self.strokeWidth
        shape.opacity = 1
        layer.addSublayer(shape)
        flashLayer = shape
        flashedFinding = current

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.25
        animation.toValue = 1.0
        animation.duration = Self.flashCycleDuration
        animation.autoreverses = true
        animation.repeatCount = 2
        shape.add(animation, forKey: "flash")

        flashGeneration += 1
        let generation = flashGeneration
        let totalDuration = Self.flashCycleDuration * Double(animation.repeatCount) * 2
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.flashGeneration == generation else { return }
                self.removeFlash()
            }
        }
    }

    /// Moves an in-flight flash to where its element is now, or takes it away when the element is
    /// gone.
    ///
    /// Called whenever ``findings`` is replaced. Leaving the flash where it was would leave a
    /// stroked rectangle describing the previous pass's geometry; removing it outright would cut
    /// nearly every flash short, because the pass that follows Scyther's screen going away lands
    /// within the flash's own 0.6 seconds.
    private func reconcileFlash() {
        if let deferred = deferredFlash, currentFinding(matching: deferred) == nil {
            deferredFlash = nil
        }
        guard let flashed = flashedFinding else { return }
        guard let current = currentFinding(matching: flashed) else {
            removeFlash()
            return
        }
        flashedFinding = current
        flashLayer?.path = UIBezierPath(roundedRect: current.frame,
                                        cornerRadius: Self.strokeCornerRadius).cgPath
    }

    /// Takes any in-flight flash off the screen.
    private func removeFlash() {
        flashLayer?.removeFromSuperlayer()
        flashLayer = nil
        flashedFinding = nil
    }
}
#endif
