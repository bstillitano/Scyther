//
//  LayoutRulerOverlayView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 9/9/2026.
//

#if !os(macOS)
import UIKit

/// The layout ruler's interactive overlay: the drag, the drawn measurement, and the control.
///
/// The first ``TopLevelView`` in Scyther that takes touches, and everything unusual about it
/// follows from that. ``GridOverlayView``, ``LayoutGuidesView`` and ``FPSCounterView`` disable
/// `isUserInteractionEnabled` outright; ``AccessibilityAuditOverlayView`` narrows itself to one
/// pill with ``AccessibilityAuditOverlayView/point(inside:with:)``. This view does neither, because
/// a ruler is a direct-manipulation tool: while it is active it must receive a drag that begins
/// anywhere on the screen, which necessarily means the app underneath receives nothing. That is
/// the whole reason ``doneButton`` exists and is always visible — see ``setActive(_:)``.
///
/// Its frame tracks its superview — ``InterfaceToolkit/topLevelViewsWrapper`` — structurally,
/// exactly as ``LayoutGuidesView``'s does: `autoresizingMask` keeps the frame in step with every
/// superview resize, ``didMoveToSuperview()`` supplies the first real frame, and
/// ``layoutSubviews()`` reacts to a bounds change that `autoresizingMask` alone would answer by
/// stretching the last-drawn content into the new shape. See ``LayoutGuidesView`` for the full
/// account, including why the wrapper itself had to be fixed first.
///
/// ## Topics
///
/// ### Activation
/// - ``setActive(_:)``
/// - ``onDone``
///
/// ### Mode
/// - ``snapsToEdges``
/// - ``onSnapModeChanged``
///
/// ### The Measurement
/// - ``measurement``
/// - ``readout(for:locale:)``
/// - ``Readout``
/// - ``readoutWidth(distance:names:availableWidth:)``
///
/// ### Coverage
/// - ``isCoveredByScyther``
/// - ``refreshForCoverageChange()``
internal class LayoutRulerOverlayView: TopLevelView {
    // MARK: - Static Data

    /// Width, in points, of the stroked measurement line.
    static let LineWidth: CGFloat = 2.0

    /// Radius, in points, of the filled dot drawn at each endpoint.
    ///
    /// The dots are what make a snap legible: without them a line that has jumped to a view's edge
    /// is indistinguishable from one that landed where the finger was.
    static let EndpointRadius: CGFloat = 4.0

    /// The colour of the line, its endpoint dots, and the readout's border.
    ///
    /// **Chosen to be unlike every other overlay Scyther draws, and the next one added should keep
    /// that going.** Taken so far: `GridOverlayView` draws red, ``GuideLine/Kind/colour`` draws
    /// blue for a safe-area inset and magenta for a layout margin, and
    /// ``AccessibilityAuditOverlayView`` draws orange issue boxes. The ruler was orange too, and
    /// with the audit's live mode on, its boxes and the ruler's line read as one feature — the
    /// reason this is green now. These overlays are deliberately usable at the same time, so hue is
    /// the only thing telling a developer which tool is speaking.
    static let MeasurementColour: UIColor = .systemGreen

    /// Font size for the distance — the answer, and the largest thing in the readout.
    static let DistanceFontSize: CGFloat = 14.0

    /// Font size for the names line, deliberately smaller than ``DistanceFontSize``: it is context
    /// for the number, not a competitor to it.
    static let NamesFontSize: CGFloat = 11.0

    /// Vertical gap between the distance and the names.
    static let ReadoutLineSpacing: CGFloat = 1.0

    /// Padding inside the readout, on every side of its text.
    static let ReadoutPadding: CGFloat = 6.0

    /// The margin the readout keeps from each edge of the overlay, and so half of what it gives up
    /// from the overlay's width — see ``readoutWidth(distance:names:availableWidth:)``.
    static let ReadoutMargin: CGFloat = 16.0

    /// Corner radius of the readout's background.
    static let ReadoutCornerRadius: CGFloat = 6.0

    /// Width of the readout's coloured border.
    static let ReadoutBorderWidth: CGFloat = 1.0

    /// Gap between the control and the bottom of the safe area.
    static let ControlBottomPadding: CGFloat = 16.0

    /// Padding inside the control, around its stack.
    static let ControlPadding: CGFloat = 10.0

    /// Corner radius of the control's blurred background.
    static let ControlCornerRadius: CGFloat = 18.0

    /// Which segment of ``modeControl`` means snapping.
    static let SnapSegment: Int = 0

    /// Which segment means free measurement.
    static let FreeSegment: Int = 1

    // MARK: - UI Elements

    /// The floating control carrying ``modeControl`` and ``doneButton``.
    ///
    /// A `UIVisualEffectView` rather than a flat colour so it stays legible over whatever the app
    /// happens to be showing underneath it, which is the whole screen and not a background this
    /// view chose.
    ///
    /// - Note: Readable rather than private so a test can check that it is hidden while Scyther's
    ///   own UI covers the app. It is still owned entirely by this view; nothing outside may
    ///   replace it.
    internal private(set) var controlContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))

    /// The Snap / Free picker.
    ///
    /// A stock `UISegmentedControl`, not a pair of hand-rolled buttons: it is exactly the control
    /// the platform provides for a two-way mode choice, and it comes with its own VoiceOver
    /// behaviour already correct.
    private let modeControl = UISegmentedControl(items: [localized("Snap"), localized("Free")])

    /// The button that dismisses the overlay.
    ///
    /// Matters far more than it looks. This view consumes every touch while it is active, so
    /// without a visible way out the only exit is the shake gesture — which does still work,
    /// because shake is a motion event rather than a touch, but a developer who does not know that
    /// is stuck inside a debugging tool.
    private let doneButton = UIButton(type: .system)

    /// The measurement's readout: how far apart the two ends are, and what they attached to.
    ///
    /// Two labels in a stack rather than one label with a newline in it, because the two lines have
    /// different rules and a single label can only have one. The distance must always be fully
    /// legible; the names may be truncated to whatever room is left. That is not a style choice —
    /// it is the whole point of the tool. A snap onto a SwiftUI list row produces a name like
    /// `_UICollectionViewListLayoutSectionBackgroundColorDecorationView.bottom`, twice, and the
    /// first version of this readout rendered both in full: a block wider and taller than the
    /// screen, clipped at both ends, with `60 pt` buried in the middle of it. Every SwiftUI screen
    /// backs onto UIKit views with names like that, so it is the normal case rather than a corner
    /// one, and the spec's tidy `Title.bottom → Subtitle.top` is what a hand-built UIKit screen
    /// gives you.
    ///
    /// Labels rather than text drawn in ``draw(_:)``, matching ``LayoutGuidesView``: text drawn
    /// into a graphics context has no line breaking, no truncation, no font scaling and no
    /// VoiceOver.
    ///
    /// - Note: Readable rather than private so a test can check where it was placed — see
    ///   ``clearOfTheControl(_:)``. It is still owned entirely by this view.
    internal private(set) var readoutContainer = UIView()

    /// The distance, on its own line. Never truncated and never clipped: the width the readout is
    /// given always fits it — see ``readoutWidth(distance:names:availableWidth:)``.
    private let distanceLabel = UILabel()

    /// What each end attached to, on one line, truncated in the middle when there is not room.
    ///
    /// Middle rather than tail truncation because both ends of these names carry information and
    /// the middle does not: `_UICollectionViewListLayout…DecorationView.bottom` still says what
    /// kind of thing it is and which edge was measured, where a tail truncation would leave
    /// `_UICollectionViewListLayoutSectionBac…` twice over and answer neither question.
    private let namesLabel = UILabel()

    // MARK: - Data

    /// The measurement currently on screen, or `nil` when there is none.
    ///
    /// In the *window's* coordinate space, not this view's, because that is the space
    /// ``LayoutRuler/measurement(from:to:in:snapping:)`` probed in; ``pointInOverlay(_:)`` converts
    /// on the way to being drawn. The two spaces coincide today — this view fills the wrapper,
    /// which fills the window — but relying on that would make the ruler wrong the first time it
    /// is hosted anywhere else.
    ///
    /// Setting it redraws the line and refreshes the readout in one step, so a caller never has to
    /// remember to ask for either.
    ///
    /// - Note: Internal rather than private so a test can put a measurement on screen without
    ///   driving a drag, which nothing available here can do.
    internal var measurement: LayoutRuler.Measurement? {
        didSet {
            guard measurement != oldValue else { return }
            refreshReadout()
            setNeedsDisplay()
        }
    }

    /// Whether the next drag snaps to view edges.
    ///
    /// This view's own copy of ``LayoutRuler/snaps``, pushed in by ``InterfaceToolkit`` and pushed
    /// back out through ``onSnapModeChanged`` — the direction of dependency every other Scyther
    /// overlay uses, where `InterfaceToolkit` configures its views and the views never reach for a
    /// settings singleton themselves.
    internal var snapsToEdges: Bool = true {
        didSet {
            modeControl.selectedSegmentIndex = snapsToEdges ? Self.SnapSegment : Self.FreeSegment
        }
    }

    /// Called when Done is tapped. ``InterfaceToolkit`` wires this to clearing
    /// ``LayoutRuler/isActive``.
    internal var onDone: (() -> Void)?

    /// Called when the picker changes, with the new value for ``LayoutRuler/snaps``.
    internal var onSnapModeChanged: ((Bool) -> Void)?

    /// `bounds` as of the last time this view reacted to its own size changing, so
    /// ``layoutSubviews()`` can tell a layout pass that changed nothing about this view's size
    /// from one that did.
    private var lastHandledBounds: CGRect = .zero

    /// The gesture driving every measurement, held so ``touchesBegan(_:with:)`` can tell a fresh
    /// touch from a second finger arriving mid-drag.
    private let pan = UIPanGestureRecognizer()

    /// Where the current drag's finger actually went down, in this view's coordinate space.
    ///
    /// Recorded in ``touchesBegan(_:with:)`` rather than derived from the pan, and that is a
    /// correctness fix rather than a tidiness one. `UIPanGestureRecognizer` zeroes its translation
    /// at *recognition* — after the slop the gesture needs to distinguish a drag from a tap — not
    /// at touch-down, so `location - translation` is the point where the gesture was recognised
    /// and not where the finger landed. Measured on the simulator: a drag of exactly 250 pt
    /// reported 210, with the start point sitting 16% of the way along the drag. A ruler that
    /// silently drops the first tens of points of every measurement is worse than no ruler.
    private var dragOrigin: CGPoint?

    // MARK: - Init

    /// Initialises the overlay, hidden, interactive, and sized to the screen until it acquires a
    /// real superview — see ``didMoveToSuperview()``.
    ///
    /// - Parameter frame: Ignored in favour of ``updateFrame()``, matching the other overlays.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    /// Required initializer for loading from a storyboard or nib.
    ///
    /// Not implemented: `LayoutRulerOverlayView` is created programmatically by
    /// ``InterfaceToolkit``.
    ///
    /// - Parameter coder: An unarchiver object.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Builds the readout, the control, and the gesture that drives everything.
    ///
    /// Starts hidden and non-modal: an overlay that swallowed the app's touches from the moment
    /// Scyther started would be indistinguishable from a frozen app. ``setActive(_:)`` is the only
    /// thing that changes either.
    private func setupUI() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isOpaque = false
        backgroundColor = .clear
        isHidden = true

        setupReadout()
        setupControl()

        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        updateFrame()
    }

    /// Configures the readout, which is positioned by ``refreshReadout()`` rather than by
    /// constraints: it follows the measurement, and the measurement is a pair of arbitrary points.
    ///
    /// The container is framed by hand and its two labels are stacked inside it with constraints,
    /// which is the same division ``setupControl()`` uses: what a view is *inside* is arithmetic,
    /// what a view contains is a fixed relationship.
    ///
    /// `.byClipping` on the distance rather than a truncation mode, because a clipped number would
    /// be a bug rather than a compromise and should look like one — ``readoutWidth(distance:names:availableWidth:)``
    /// guarantees the width always fits it. The border is the readout's only colour: white on near
    /// black is the legible pairing, and the tie to the line it describes is better made by an
    /// outline than by tinting the number the developer came to read.
    private func setupReadout() {
        distanceLabel.font = .monospacedDigitSystemFont(ofSize: Self.DistanceFontSize, weight: .bold)
        distanceLabel.textColor = .white
        distanceLabel.textAlignment = .center
        distanceLabel.numberOfLines = 1
        distanceLabel.lineBreakMode = .byClipping

        namesLabel.font = .systemFont(ofSize: Self.NamesFontSize, weight: .regular)
        namesLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        namesLabel.textAlignment = .center
        namesLabel.numberOfLines = 1
        namesLabel.lineBreakMode = .byTruncatingMiddle

        let stack = UIStackView(arrangedSubviews: [distanceLabel, namesLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Self.ReadoutLineSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        readoutContainer.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        readoutContainer.layer.cornerRadius = Self.ReadoutCornerRadius
        readoutContainer.layer.borderWidth = Self.ReadoutBorderWidth
        readoutContainer.layer.borderColor = Self.MeasurementColour.cgColor
        readoutContainer.clipsToBounds = true
        readoutContainer.isHidden = true
        readoutContainer.addSubview(stack)
        addSubview(readoutContainer)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: readoutContainer.topAnchor, constant: Self.ReadoutPadding),
            stack.bottomAnchor.constraint(equalTo: readoutContainer.bottomAnchor, constant: -Self.ReadoutPadding),
            stack.leadingAnchor.constraint(equalTo: readoutContainer.leadingAnchor, constant: Self.ReadoutPadding),
            stack.trailingAnchor.constraint(equalTo: readoutContainer.trailingAnchor, constant: -Self.ReadoutPadding)
        ])
    }

    /// Lays the control out against the safe area, so it clears the home indicator on a device
    /// with one and the screen edge on a device without.
    ///
    /// Auto Layout here, and frames everywhere else in this file, is deliberate rather than
    /// inconsistent: the control's position is a fixed relationship to an edge, which is precisely
    /// what constraints express well, while the readout's position is arithmetic
    /// (``LayoutRulerGeometry/labelOrigin(midpoint:labelSize:in:)``) that no constraint can state.
    private func setupControl() {
        modeControl.selectedSegmentIndex = Self.SnapSegment
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        var configuration = UIButton.Configuration.filled()
        configuration.title = localized("Done")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        doneButton.configuration = configuration
        // No `accessibilityLabel` of its own: `UIButton` derives one from its configuration's
        // title, so setting the same localised string again would only imply the title was not
        // being announced.
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [modeControl, doneButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.layer.cornerRadius = Self.ControlCornerRadius
        controlContainer.clipsToBounds = true
        controlContainer.contentView.addSubview(stack)
        addSubview(controlContainer)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: controlContainer.contentView.topAnchor,
                                       constant: Self.ControlPadding),
            stack.bottomAnchor.constraint(equalTo: controlContainer.contentView.bottomAnchor,
                                          constant: -Self.ControlPadding),
            stack.leadingAnchor.constraint(equalTo: controlContainer.contentView.leadingAnchor,
                                           constant: Self.ControlPadding),
            stack.trailingAnchor.constraint(equalTo: controlContainer.contentView.trailingAnchor,
                                            constant: -Self.ControlPadding),
            controlContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            controlContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor,
                                                     constant: -Self.ControlBottomPadding)
        ])
    }

    // MARK: - Activation

    /// Shows or hides the overlay, and takes VoiceOver with it.
    ///
    /// `accessibilityViewIsModal` is set only while the overlay is on screen. The ruler is a
    /// direct-manipulation tool with no non-visual equivalent — a drag between two screen points
    /// is not meaningful to a screen reader, and a VoiceOver user cannot perform one — so the bar
    /// it has to clear is not "usable" but "breaks nothing": while it is up, VoiceOver must not
    /// wander into an app the developer cannot see or reach, and when it is down it must not still
    /// be trapping anyone. Leaving the flag permanently `true` would do exactly that, because a
    /// hidden view is ignored by UIAccessibility today and nothing guarantees it always will be.
    ///
    /// Deactivating clears ``measurement`` as well. A measurement kept across a deactivation would
    /// be redrawn the next time the ruler was switched on, against whatever the app is showing by
    /// then — the same staleness ``updateFrame()`` clears it for after a rotation.
    ///
    /// - Parameter active: Whether the overlay should be on screen and taking touches.
    internal func setActive(_ active: Bool) {
        isHidden = !active
        accessibilityViewIsModal = active

        if active {
            applyCoverage()
            // The escape hatch, announced first: a VoiceOver user who cannot use this tool must
            // still land on the control that dismisses it.
            UIAccessibility.post(notification: .screenChanged, argument: doneButton)
        } else {
            measurement = nil
        }
    }

    // MARK: - Frame Updates

    /// Gives the view its first real frame the moment it actually has a superview to size itself
    /// against — `init(frame:)` cannot, since `superview` is always `nil` there.
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateFrame()
    }

    /// Reacts whenever a layout pass leaves this view an actually different size.
    ///
    /// Guarded on ``lastHandledBounds`` so the layout passes the control's own constraints
    /// generate — which change this view's `bounds` not at all — cost one comparison rather than
    /// throwing away the developer's measurement.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastHandledBounds else { return }
        handleNewBounds()
    }

    /// Resizes the overlay to match its superview, or to the screen if it has none yet, and clears
    /// the measurement *if that actually changed this view's size*.
    ///
    /// `superview?.bounds ?? UIScreen.main.bounds` matches ``LayoutGuidesView/updateFrame()``:
    /// called from `init` before there is a superview, `.zero` would produce a view that is never
    /// asked to draw.
    ///
    /// The bounds guard is the whole point of this method reading the way it does, and it is not
    /// an optimisation. `TopLevelViewsWrapper.deviceDidChangeOrientation` calls this on every child
    /// for `UIDevice.orientationDidChangeNotification`, which fires for `.faceUp` and `.faceDown`
    /// and for rotations a portrait-locked app never honours — none of which moves a single view.
    /// Clearing unconditionally meant laying the phone flat erased a measurement the developer was
    /// still reading, which is the opposite of "a measurement persists after the finger lifts".
    /// The spec clears a measurement because "its endpoints described a layout that no longer
    /// exists", so the trigger has to be the layout actually changing, not a notification arriving.
    internal override func updateFrame() {
        frame = superview?.bounds ?? UIScreen.main.bounds
        guard bounds != lastHandledBounds else { return }
        handleNewBounds()
    }

    /// Clears the measurement and repaints for a size that has just changed.
    ///
    /// The measurement goes because its endpoints describe a layout that no longer exists: after a
    /// rotation, "16 pt between these two labels" is a statement about where those labels used to
    /// be. Keeping the line and stretching it into the new aspect ratio — which is what a `UIView`
    /// does by default, `contentMode` being `.scaleToFill` — would be worse than keeping nothing,
    /// because it would still look like an answer.
    private func handleNewBounds() {
        lastHandledBounds = bounds
        measurement = nil
        setNeedsDisplay()
    }

    // MARK: - Actions

    /// Forwards a tap on Done to ``onDone``.
    @objc
    private func doneTapped() {
        onDone?()
    }

    /// Forwards a change of mode to ``onSnapModeChanged``.
    ///
    /// Does not touch ``measurement``: re-snapping the answer already on screen would silently
    /// rewrite a number the developer is in the middle of reading. The new mode applies to the
    /// next drag.
    @objc
    private func modeChanged() {
        snapsToEdges = modeControl.selectedSegmentIndex == Self.SnapSegment
        onSnapModeChanged?(snapsToEdges)
    }

    /// Turns a drag into a measurement.
    ///
    /// The start point comes from ``dragOrigin`` — the real touch-down, recorded in
    /// ``touchesBegan(_:with:)``. There is deliberately no `location - translation` fallback: it is
    /// unreachable, because `touchesBegan(_:with:)` runs for every touch this view hit-tests before
    /// the pan can recognise, and if it ever did run it would silently reintroduce the very error
    /// ``dragOrigin`` exists to fix. Measuring nothing is the honest answer to a drag whose start
    /// was never seen.
    ///
    /// Every state that has moved recomputes the measurement, so the line and its number track the
    /// finger. `.ended` recomputes once more and then leaves it: a measurement persists after the
    /// finger lifts so it can be read, and is replaced by the next drag.
    ///
    /// - Parameter recogniser: The pan driving the measurement.
    @objc
    private func handlePan(_ recogniser: UIPanGestureRecognizer) {
        guard let window else { return }

        switch recogniser.state {
        case .began, .changed, .ended:
            guard let origin = dragOrigin else { return }
            let current = recogniser.location(in: self)
            measurement = LayoutRuler.measurement(from: convert(origin, to: window),
                                                  to: convert(current, to: window),
                                                  in: window,
                                                  snapping: snapsToEdges)
            if recogniser.state == .ended { dragOrigin = nil }

        case .cancelled, .failed:
            dragOrigin = nil
            measurement = nil

        default:
            break
        }
    }

    /// Records where a drag really began, and clears the measurement when the developer taps
    /// rather than drags.
    ///
    /// A tap is how the readout is dismissed, and a pan recogniser never fires for one — it
    /// requires movement by definition. Touches that land on the control are delivered to the
    /// control itself and never reach here, so tapping Done or the picker does not disturb
    /// anything.
    ///
    /// Ignored while a pan is already running, so a second finger arriving mid-drag neither moves
    /// the measurement's start nor wipes the measurement being made.
    ///
    /// - Parameters:
    ///   - touches: The touches that began.
    ///   - event: The event they belong to.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard pan.state == .possible, let touch = touches.first else { return }
        dragOrigin = touch.location(in: self)
        measurement = nil
    }

    // MARK: - The Readout

    /// What the readout says for a measurement.
    ///
    /// Static and pure so the wording is testable — an overlay's drawing is not, and a readout
    /// that names the wrong thing is exactly the failure a ruler cannot afford.
    ///
    /// A snapped measurement names both ends and then gives the distance, because "40 pt" alone
    /// leaves open the question the developer is actually asking, which is *between what*. A free
    /// measurement carries the distance alone: it attached to nothing, and inventing a name would
    /// be a lie. A half-snapped measurement — one end on a view, the other over nothing the probe
    /// would descend into — says so with ``freeEndpointName``, rather than dropping to a bare
    /// number and hiding that half of it did snap.
    ///
    /// The distance is formatted, not translated, and keeps one decimal place. Rounding `16.5` to
    /// `16` would hide precisely the discrepancy someone reached for a ruler to find.
    ///
    /// - Parameters:
    ///   - measurement: The measurement to describe.
    ///   - locale: The locale the number is formatted in. Defaults to the effective language's,
    ///     so the decimal separator matches the words around it.
    /// - Returns: The distance, and the names when there are any.
    internal static func readout(for measurement: LayoutRuler.Measurement,
                                 locale: Locale = LanguageOverride.shared.namingLocale) -> Readout {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        let number = formatter.string(from: NSNumber(value: Double(measurement.distance)))
            ?? "\(measurement.distance)"
        let distance = localized("\(number) pt")

        guard measurement.startDescription != nil || measurement.endDescription != nil else {
            return Readout(distance: distance, names: nil)
        }

        let start = displayName(measurement.startDescription)
        let end = displayName(measurement.endDescription)
        return Readout(distance: distance, names: localized("\(start) → \(end)"))
    }

    /// How wide the readout may be.
    ///
    /// Pure and static because this is the decision that went wrong: the first version handed
    /// ``LayoutRulerGeometry/labelOrigin(midpoint:labelSize:in:)`` whatever size the text wanted,
    /// and that function clamps an origin rather than a size, so a readout wider than the screen
    /// was placed at `x = 0` and ran off both edges. The cap belongs before the placement, and
    /// somewhere a test can reach it.
    ///
    /// Answers the width of the readout's *content*, and the cap it applies already gives up
    /// ``ReadoutPadding`` on each side as well as ``ReadoutMargin``, so the box drawn around that
    /// content still fits inside the overlay less its margins. Getting that wrong is how a
    /// twelve-point overhang gets shipped.
    ///
    /// The readout is as wide as its widest line, and never wider than that cap. When the cap
    /// bites it is the names that give way, because
    /// they are the only line that may be truncated; the distance is always narrower than the cap
    /// in practice — it is a number and a unit — and if it somehow were not, the cap would still
    /// win, since a readout running off the screen answers nothing at all.
    ///
    /// - Parameters:
    ///   - distance: The natural width of the distance line.
    ///   - names: The natural width of the names line, or `0` when there are no names.
    ///   - availableWidth: The overlay's width.
    /// - Returns: The width to give the readout's content, never negative.
    internal static func readoutWidth(distance: CGFloat,
                                      names: CGFloat,
                                      availableWidth: CGFloat) -> CGFloat {
        let cap = max(0, availableWidth - (ReadoutMargin + ReadoutPadding) * 2)
        return min(max(distance, names), cap)
    }

    /// One end's name as the readout shows it.
    ///
    /// Drops a leading underscore, because every name that needs it is a private UIKit class —
    /// `_UITouchPassthroughView`, `_UICollectionViewListLayout…` — and the underscore is the one
    /// character in them that carries nothing for a developer measuring a gap. Dropped here rather
    /// than in ``LayoutRuler/measurement(from:to:in:snapping:)`` so the measurement keeps the class's
    /// real name and only the display is tidied.
    ///
    /// - Parameter description: The endpoint's description, or `nil` when it attached to nothing.
    /// - Returns: The name to show, or ``freeEndpointName`` for an endpoint that attached to
    ///   nothing.
    private static func displayName(_ description: String?) -> String {
        guard let description else { return freeEndpointName }
        return description.hasPrefix("_") ? String(description.dropFirst()) : description
    }

    /// What an endpoint that attached to nothing is called in the readout.
    ///
    /// Named rather than left blank so a half-snapped measurement reads as one: the spec's rule is
    /// that an endpoint with nothing under it "falls back to the free point, and the readout says
    /// so rather than reporting a snap that did not happen".
    private static var freeEndpointName: String { localized("free point") }

    /// Rebuilds the readout for the current ``measurement`` and puts it where it can be read.
    ///
    /// The single owner of ``readoutContainer``'s visibility: there is one rule — a readout is shown
    /// when there is a measurement and Scyther is not in front of the app — and it is stated here
    /// only. ``applyCoverage()`` changes what the answer is and then calls this rather than
    /// computing a second copy of it.
    ///
    /// Positioned by ``LayoutRulerGeometry/labelOrigin(midpoint:labelSize:in:)`` — the same rule
    /// ``LayoutGuidesView`` uses for its own labels — so a measurement taken near an edge of the
    /// screen does not place its own answer off it.
    private func refreshReadout() {
        guard let measurement, !isCoveredByScyther() else {
            readoutContainer.isHidden = true
            return
        }

        readoutContainer.isHidden = false

        let readout = Self.readout(for: measurement)
        distanceLabel.text = readout.distance
        namesLabel.text = readout.names
        namesLabel.isHidden = readout.names == nil

        let start = pointInOverlay(measurement.start)
        let end = pointInOverlay(measurement.end)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        // The labels' *natural* sizes, unconstrained: `sizeThatFits` on a single-line label reports
        // the width the text wants rather than the width it will get, which is exactly what the cap
        // below needs to compare against. The truncation then happens because the frame is narrower
        // than that, which is UILabel's own job and not something to compute here.
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        let distanceSize = distanceLabel.sizeThatFits(unbounded)
        let namesSize = namesLabel.isHidden ? CGSize.zero : namesLabel.sizeThatFits(unbounded)

        let contentWidth = Self.readoutWidth(distance: distanceSize.width,
                                             names: namesSize.width,
                                             availableWidth: bounds.width)
        let contentHeight = distanceSize.height
            + (namesLabel.isHidden ? 0 : namesSize.height + Self.ReadoutLineSpacing)

        let size = CGSize(width: contentWidth + Self.ReadoutPadding * 2,
                          height: contentHeight + Self.ReadoutPadding * 2)
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: midpoint, labelSize: size, in: bounds.size)
        readoutContainer.frame = clearOfTheControl(withinMargins(CGRect(origin: origin, size: size)))
        readoutContainer.layoutIfNeeded()
    }

    /// Keeps the readout inside the same margin its width was capped against.
    ///
    /// ``readoutWidth(distance:names:availableWidth:)`` gives up ``ReadoutMargin`` on each side so
    /// the readout can never be wider than the space between the margins, but
    /// ``LayoutRulerGeometry/labelOrigin(midpoint:labelSize:in:)`` clamps to the overlay's *bounds*
    /// — it knows nothing about a margin — so a measurement near an edge still ended up with the
    /// readout flush against it, touching the screen. Reserving the room and then not using it is
    /// the sort of half-applied rule that reads as a bug.
    ///
    /// Horizontal only. The vertical position has ``clearOfTheControl(_:)`` to answer to, and a
    /// second clamp on the same axis would be two rules fighting over one number.
    ///
    /// - Parameter frame: The readout's frame as the geometry placed it.
    /// - Returns: The same frame, moved inside the margins.
    private func withinMargins(_ frame: CGRect) -> CGRect {
        let rightmost = max(Self.ReadoutMargin, bounds.width - Self.ReadoutMargin - frame.width)
        var inset = frame
        inset.origin.x = min(max(Self.ReadoutMargin, frame.origin.x), rightmost)
        return inset
    }

    /// Lifts a readout that would land underneath the floating control.
    ///
    /// ``LayoutRulerGeometry/labelOrigin(midpoint:labelSize:in:)`` clamps to the overlay's bounds
    /// and knows nothing about the control, so a measurement whose midpoint sits near the bottom
    /// centre of the screen puts its own answer behind an opaque blur. Fixed here rather than in
    /// the geometry because the control is a fact about *this view* — its size, its padding, its
    /// safe-area constraint — and pushing that into a pure function that four other things call
    /// would be leaking one view's furniture into shared arithmetic.
    ///
    /// Moves the readout above the control rather than below it, and never above the top of the
    /// overlay: a readout clipped by the top edge is a worse failure than one sitting a little
    /// higher than the midpoint it describes.
    ///
    /// - Parameter frame: The readout's frame as the geometry placed it.
    /// - Returns: The same frame, lifted clear of the control if it needed to be.
    private func clearOfTheControl(_ frame: CGRect) -> CGRect {
        guard !controlContainer.isHidden, frame.intersects(controlContainer.frame) else { return frame }

        var lifted = frame
        lifted.origin.y = max(0, controlContainer.frame.minY - frame.height - Self.ReadoutPadding)
        return lifted
    }

    // MARK: - Hit Testing

    /// Whether Scyther's own UI is in front of the app.
    ///
    /// Injected the way ``AccessibilityAuditOverlayView/isCoveredByScyther`` is, so a test can put
    /// Scyther "in front" without presenting anything.
    internal var isCoveredByScyther: @MainActor () -> Bool = { ScytherPresentation.isCoveringScreen }

    /// Reports this view as containing nothing at all while Scyther's own UI is in front of the
    /// app.
    ///
    /// This is the escape hatch behind the escape hatch. ``TopLevelViewsWrapper`` is kept at the
    /// front of the key window — ``InterfaceToolkit`` brings it back whenever the window's layers
    /// change — so a screen Scyther presents can end up *under* this overlay, and an overlay that
    /// swallows every touch would then swallow the menu's as well: shake to open the menu while the
    /// ruler is active, and nothing in it responds. Measured on the simulator the menu does come
    /// out in front and stays usable, but that is view ordering rather than a rule, and the rule is
    /// cheap: while Scyther is covering the app, the app is not what is on screen, so there is
    /// nothing here to measure and no reason to take a touch.
    ///
    /// - Parameters:
    ///   - point: The point to test, in this view's own coordinate space.
    ///   - event: The event the point came from.
    /// - Returns: `false` whenever Scyther is covering the app, and otherwise whatever `UIView`
    ///   would have said.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isCoveredByScyther() else { return false }
        return super.point(inside: point, with: event)
    }

    // MARK: - Drawing

    /// Strokes the measurement line and a dot at each end.
    ///
    /// The readout is a subview and is not drawn here — see ``refreshReadout()``.
    ///
    /// Draws nothing while Scyther's own UI is in front of the app, for the reason
    /// ``AccessibilityAuditOverlayView/draw(_:)`` does not either: a measurement describes two
    /// points on the app, so stroked across Scyther's own menu it is not merely untidy but wrong.
    /// ``refreshForCoverageChange()`` is what brings it back.
    ///
    /// - Parameter rect: The portion of the view's bounds that needs to be updated.
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard !isCoveredByScyther() else { return }
        guard let measurement, let context = UIGraphicsGetCurrentContext() else { return }

        let start = pointInOverlay(measurement.start)
        let end = pointInOverlay(measurement.end)

        context.setStrokeColor(Self.MeasurementColour.cgColor)
        context.setFillColor(Self.MeasurementColour.cgColor)
        context.setLineWidth(Self.LineWidth)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        for point in [start, end] {
            let dot = CGRect(x: point.x - Self.EndpointRadius,
                             y: point.y - Self.EndpointRadius,
                             width: Self.EndpointRadius * 2,
                             height: Self.EndpointRadius * 2)
            context.fillEllipse(in: dot)
        }
    }

    /// Re-reads ``isCoveredByScyther`` and repaints.
    ///
    /// Called by ``InterfaceToolkit`` when ``ScytherPresentation/coverageDidChangeNotification``
    /// arrives. Nothing else would: a screen appearing over the app changes no frame this view
    /// owns, so no layout pass and no `draw(_:)` follows on its own.
    ///
    /// The measurement itself is kept. Unlike a rotation, a modal appearing and going away again
    /// leaves the app underneath exactly where it was, so the answer on screen is still the answer.
    internal func refreshForCoverageChange() {
        applyCoverage()
    }

    /// Hides everything this view puts on screen while Scyther's own UI is in front of the app.
    ///
    /// The control is hidden for the reason ``AccessibilityAuditOverlayView`` hides its pill:
    /// ``TopLevelViewsWrapper`` is kept at the front of the key window, so a screen Scyther
    /// presents can end up *under* this overlay — measured on the simulator, shaking to open the
    /// menu while the ruler is active does exactly that, and left visible the control floats over
    /// the menu's own search field looking like part of it. ``point(inside:with:)`` already stops
    /// it stealing the menu's touches; this stops it claiming the menu's pixels.
    private func applyCoverage() {
        controlContainer.isHidden = isCoveredByScyther()
        refreshReadout()
        setNeedsDisplay()
    }

    /// Converts a point from the space the measurement was taken in — the window's — into this
    /// view's own.
    ///
    /// Falls back to the point unchanged when there is no window, which is the case in a test and
    /// is also the identity in practice, since this view fills the wrapper and the wrapper fills
    /// the window.
    ///
    /// - Parameter point: The point, in window coordinates.
    /// - Returns: The same point in this view's coordinate space.
    private func pointInOverlay(_ point: CGPoint) -> CGPoint {
        guard let window else { return point }
        return convert(point, from: window)
    }
}

// MARK: - Readout

extension LayoutRulerOverlayView {
    /// What the readout says, split into the two lines that have different rules.
    ///
    /// A value type rather than one string with a newline in it, because the split *is* the
    /// behaviour: the distance is the answer and is always shown in full, and the names are context
    /// that may be truncated to whatever room is left. Returning them separately is what lets a
    /// test state that rule, and what stops it being re-decided inside a `draw(_:)` or a label's
    /// configuration where nothing can check it.
    struct Readout: Equatable, Sendable {
        /// The distance and its unit, formatted in the effective locale. Always shown in full.
        let distance: String

        /// What each end attached to, or `nil` for a free measurement, which attached to nothing
        /// and has nothing to name.
        let names: String?
    }
}

// MARK: - UIGestureRecognizerDelegate

extension LayoutRulerOverlayView: UIGestureRecognizerDelegate {
    /// Refuses a drag that begins on the ruler's own control.
    ///
    /// Two reasons, and the second is the load-bearing one. A `UISegmentedControl` is changed by
    /// dragging across it as well as by tapping, so a pan that begins on the picker would cancel
    /// the control's own tracking and make the picker unusable. And a drag that began there would
    /// draw a measurement between two points on Scyther's own interface — the probe already
    /// refuses to snap to anything of Scyther's — it measures the app *underneath* the control —
    /// so the result would be a measurement of whatever happens to lie beneath the picker, which
    /// is not what a drag across a picker was asking for.
    ///
    /// - Parameters:
    ///   - gestureRecognizer: The pan.
    ///   - touch: The touch that would start it.
    /// - Returns: `false` for a touch on the control, `true` everywhere else.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return true }
        return !touched.isDescendant(of: controlContainer)
    }
}
#endif
