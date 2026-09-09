//
//  LayoutGuidesView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/9/2026.
//

#if !os(macOS)
import UIKit

/// One drawn guide: where it runs and what it measures.
///
/// A plain value type rather than something read back off ``LayoutGuidesView``'s subviews, so
/// the placement rules can be exercised by a test without a window, a superview, or a run loop —
/// see ``LayoutGuidesView/guideLines(safeArea:margins:in:)``.
struct GuideLine: Equatable, Sendable {
    /// What the line represents, which decides its colour and stroke style in
    /// ``LayoutGuidesView/draw(_:)``.
    enum Kind: Sendable {
        /// Drawn at a `UIWindow`'s safe-area inset.
        case safeArea

        /// Drawn at the root view's layout margin.
        case margin
    }

    /// Where the line begins, in the overlay's own bounds.
    let start: CGPoint

    /// Where the line ends, in the overlay's own bounds.
    let end: CGPoint

    /// The inset this line marks, in points. Not necessarily a whole number — see
    /// ``roundedValue``, which is what the label actually reads.
    let value: CGFloat

    /// Whether this is a safe-area line or a layout-margin line.
    let kind: Kind

    /// The value rounded to whole points, matching what the label reads.
    ///
    /// A sub-point inset such as `0.33` is real and passes ``LayoutGuidesView/guideLines(safeArea:margins:in:)``'s
    /// visibility guard once rounded, but truncating it to `0` for display would print exactly
    /// the noise that guard exists to prevent. Rounding, not truncation, is also what that guard
    /// itself is written against, so a line only exists here at all when this value is non-zero.
    var roundedValue: Int {
        Int(value.rounded())
    }

    /// Where this line's label should be centred, as a fraction along `start`–`end`.
    ///
    /// A root view's `layoutMargins` are inset from the safe area by default, so on the common
    /// device — a notch or a home indicator, no custom margins — a margin line lands at exactly
    /// the same coordinates as a safe-area line and would otherwise paint directly over it,
    /// erasing both the line and the label that was meant to distinguish them. Placing the two
    /// kinds' labels at different fractions along the same coincident line keeps both legible
    /// without changing where either line is actually drawn — ``start`` and ``end`` still mark
    /// the true measurement, which is what a test, and a developer measuring by eye, both read.
    var labelMidpoint: CGPoint {
        let fraction: CGFloat = kind == .safeArea ? 1.0 / 3.0 : 2.0 / 3.0
        return CGPoint(x: start.x + (end.x - start.x) * fraction,
                       y: start.y + (end.y - start.y) * fraction)
    }
}

extension GuideLine.Kind {
    /// The stroke and label colour for this kind of line.
    ///
    /// Two distinct hues rather than one, because a safe-area inset and a layout margin can sit
    /// only a few points apart — a leading margin just inside a leading safe area, say — and a
    /// developer has to be able to tell which is which without hovering over the label.
    var colour: UIColor {
        switch self {
        case .safeArea:
            return .systemBlue

        case .margin:
            return .systemPurple
        }
    }

    /// Whether this kind strokes as a dashed line rather than a solid one.
    ///
    /// The second half of telling a coincident safe-area line and margin line apart — see
    /// ``GuideLine/labelMidpoint`` for the first half. Colour alone cannot separate two lines
    /// drawn at identical coordinates, since the one stroked second simply paints over the one
    /// stroked first; a different dash pattern means both remain visible regardless of paint
    /// order.
    var isDashed: Bool {
        switch self {
        case .safeArea:
            return false

        case .margin:
            return true
        }
    }
}

/// Draws the key window's safe-area insets and layout margins.
///
/// A `TopLevelView` like ``GridOverlayView``: no touches, no state beyond its setting, redrawn
/// on ``updateFrame()``. Unlike ``GridOverlayView``, it holds no configuration of its own —
/// there is no size or colour to pick — so everything it draws is read fresh from the window.
///
/// Its frame tracks its superview — ``InterfaceToolkit/topLevelViewsWrapper`` — structurally
/// rather than by being told. Four things cooperate to make that true at every moment the view
/// exists rather than only after the next rotation notification happens to fire:
///
/// 1. ``autoresizingMask`` is set to `[.flexibleWidth, .flexibleHeight]`, so UIKit itself keeps
///    this view's `frame` equal to its superview's `bounds` through every superview resize —
///    including a rotation — without this view doing anything at all.
/// 2. ``didMoveToSuperview()`` gives the view its first real frame the moment it actually has a
///    superview to size itself against, rather than in `init`, when `superview` is always `nil`
///    and the frame would otherwise stay `.zero` — and a zero-sized view is never asked to draw.
/// 3. ``layoutSubviews()`` repaints whenever `bounds` has actually changed, which is what makes
///    a rotation correct rather than merely present: `contentMode` defaults to `.scaleToFill`, so
///    a bounds change alone does not schedule a fresh `draw(_:)` — it stretches whatever was
///    last drawn into the new size, which is precisely what "the guides describe the previous
///    orientation" looks like.
/// 4. ``safeAreaInsetsDidChange()`` repaints when the insets change even on the rare occasion
///    that arrives without a `bounds` change of its own — see that method's own doc comment.
///
/// (1)–(3) alone were not enough on their own the first time this was fixed: `autoresizingMask`
/// only makes this view follow *its superview*, and `TopLevelViewsWrapper` was itself sizing
/// itself from `UIScreen.main.bounds`, sampled inside a `UIDevice.orientationDidChangeNotification`
/// handler with no guarantee that value had caught up to the new orientation yet — one rotation
/// behind, throughout a full round trip. This view's own structural fix could not fix a stale
/// superview; `TopLevelViewsWrapper` needed the same treatment, sizing itself from `window.bounds`
/// with its own `autoresizingMask`, before (1)–(3) here meant anything. See
/// `TopLevelViewsWrapper`'s own doc comment for that half of the story. `updateFrame()` still
/// exists and does real work regardless, because `TopLevelView` requires the override and the
/// wrapper still calls it: see ``updateFrame()``.
internal class LayoutGuidesView: TopLevelView {
    // MARK: - Static Data

    /// Width, in points, of every stroked guide line.
    static let LineWidth: CGFloat = 1.0

    /// Font size for each line's `"N pt"` label.
    static let LabelFontSize: CGFloat = 9.0

    /// Horizontal padding inside a label, on each side of its text.
    static let LabelHorizontalPadding: CGFloat = 4.0

    /// The smallest distance a label may sit from any edge of the overlay.
    ///
    /// Small — these labels annotate lines that are themselves only a few points from an edge, and
    /// a large margin would drag a label away from the line it names. Not zero, because a label
    /// clamped flush against the screen reads as one that has been clipped rather than one that has
    /// been placed, which is the failure the ruler's readout was already fixed for. Passed to
    /// ``LayoutRulerGeometry/labelOrigin(midpoint:labelSize:in:margin:)`` so both tools take their
    /// margin in the one place rather than each clamping again afterwards.
    ///
    /// Smaller than ``LayoutRulerOverlayView/ReadoutMargin``, which is the ruler's equivalent: this
    /// label is a 9-point number in a 4-point-padded box, and an inset the size of the ruler's
    /// would move it further from its own line than the line is from the edge. Large enough to
    /// read as placed rather than clipped, which is the whole point of it being non-zero.
    static let LabelMargin: CGFloat = 8.0

    /// The dash pattern used for a margin line's stroke — see ``GuideLine/Kind/isDashed``.
    static let MarginDashPattern: [CGFloat] = [4, 3]

    // MARK: - UI Elements

    /// The labels for the current set of lines, laid out in ``layoutSubviews()`` rather than in
    /// ``draw(_:)``: mutating the view hierarchy — adding and removing subviews — during a render
    /// pass works, but `layoutSubviews()` is where UIKit expects that kind of work to happen, and
    /// doing it there also means a plain re-layout (a superview resize) refreshes the labels'
    /// positions without necessarily forcing every label to be torn down and rebuilt on every
    /// single `draw(_:)` this view is asked for.
    ///
    /// Rebuilt in full, rather than reused, because the *count* varies with how many insets are
    /// non-zero — anywhere from zero to eight — so there is no fixed pool the way
    /// ``GridOverlayView``'s two permanent labels are.
    private var labels: [UILabel] = []

    /// The lines from the most recent ``layoutLabels()`` pass — what ``draw(_:)`` strokes.
    ///
    /// Computed in ``layoutLabels()`` rather than inside ``draw(_:)`` itself, so ``draw(_:)``'s
    /// only job is to stroke what has already been decided, matching
    /// ``guideLines(safeArea:margins:in:)``'s whole reason for existing: an overlay's drawing
    /// cannot be inspected by a test, so nothing that has a right answer should be decided only
    /// there.
    private var lines: [GuideLine] = []

    /// `bounds` as of the last time this view reacted to its own size changing, so
    /// ``layoutSubviews()`` can tell a layout pass that changed nothing about this view's size
    /// from one that did.
    ///
    /// Named as ``LayoutRulerOverlayView`` and ``TopLevelViewsWrapper`` name theirs: the three are
    /// the same guard, and a reader tracing a rotation through all three should not have to work
    /// out three times that they are.
    private var lastHandledBounds: CGRect = .zero

    // MARK: - Init

    /// Initialises the overlay, non-interactive and briefly sized to the screen until it
    /// acquires a real superview — see ``didMoveToSuperview()``.
    ///
    /// - Parameter frame: Ignored in favour of ``updateFrame()``, matching ``GridOverlayView``.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    /// Required initializer for loading from a storyboard or nib.
    ///
    /// Not implemented: `LayoutGuidesView` is created programmatically by ``InterfaceToolkit``.
    ///
    /// - Parameter coder: An unarchiver object
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures the view to take no touches, to track its superview's size automatically, and
    /// to draw nothing of its own until ``draw(_:)`` strokes the current guides.
    ///
    /// `accessibilityElementsHidden` is set here, and not merely inherited from
    /// `isUserInteractionEnabled = false`, because a screen reader can still describe a
    /// non-interactive view's frame — a guide line has nothing to say to VoiceOver, and every
    /// other overlay in Scyther keeps quiet the same way.
    private func setupUI() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isUserInteractionEnabled = false
        isOpaque = false
        accessibilityElementsHidden = true
        updateFrame()
    }

    /// Gives the view its first real frame the moment it actually has a superview to size itself
    /// against.
    ///
    /// `init(frame:)` cannot do this: `superview` is always `nil` at that point, so a frame set
    /// there can only ever be a guess — `UIScreen.main.bounds`, ``updateFrame()``'s own fallback
    /// — rather than the real answer. Once this view is added to
    /// ``InterfaceToolkit/topLevelViewsWrapper``, ``autoresizingMask`` takes over keeping the
    /// frame in step with every subsequent superview resize; this is only the one moment
    /// autoresizing itself does not cover, because autoresizing reacts to a superview's bounds
    /// *changing*, and attaching to a superview for the first time is not a change to
    /// anything — it is the frame's very first value.
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateFrame()
    }

    /// Repaints whenever a layout pass leaves this view an actually different size.
    ///
    /// This, together with ``autoresizingMask``, is what makes a rotation correct rather than
    /// merely eventually present: `UIView`'s default `contentMode` is `.scaleToFill`, so
    /// `autoresizingMask` alone would keep this view's *frame* correct through a rotation while
    /// silently stretching whatever was last drawn into the new aspect ratio — which is exactly
    /// what lines describing the previous orientation looks like. Guarded on
    /// ``lastHandledBounds`` so a layout pass that leaves `bounds` unchanged — this view has
    /// no subviews whose own layout would trigger one, but a superview's unrelated layout pass
    /// can still call this — costs nothing beyond the comparison.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastHandledBounds else { return }
        refreshGuides()
    }

    /// Repaints when the safe area changes without necessarily changing `bounds`.
    ///
    /// UIKit's own hook for exactly this, called only after the new insets are already correct
    /// — unlike `deviceDidChangeOrientation`'s notification, there is no ordering question here.
    /// Needed because ``layoutSubviews()`` above only fires on a *bounds* change: a rotation
    /// normally changes both together, but the two are not guaranteed to arrive as a single
    /// event, and a device that changes its safe area without changing its bounds at all — a
    /// notch appearing behind a status-bar-height change, for one — would otherwise leave this
    /// view's insets stale with nothing to notice. Calls ``refreshGuides()`` rather than a bare
    /// `setNeedsDisplay()`: ``draw(_:)`` only strokes the already-computed ``lines``, so a redraw
    /// with nothing recomputed would just repaint the same stale lines — the insets have to be
    /// re-read, not merely asked to be shown again.
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        refreshGuides()
    }

    /// Resizes the overlay to match its superview, or to the screen if it has none yet, and
    /// refreshes the guides.
    ///
    /// Kept, and kept doing real work, for two reasons. `TopLevelView` requires the override, and
    /// `TopLevelViewsWrapper.deviceDidChangeOrientation` still calls it directly on every
    /// `TopLevelView` it holds — this view's own ``autoresizingMask``/``layoutSubviews()`` pair
    /// makes that call redundant for keeping the *frame* correct, but not for keeping the guides
    /// themselves fresh: a rotation can change `window?.safeAreaInsets` and the root view's
    /// `layoutMargins` independently of whether this view's own `bounds` size happens to change,
    /// so this always refreshes rather than gating on ``lastHandledBounds`` the way
    /// ``layoutSubviews()`` does.
    ///
    /// `superview?.bounds ?? UIScreen.main.bounds`, matching
    /// `AccessibilityAuditOverlayView.updateFrame()`, rather than `?? .zero`: called from `init`
    /// before there is a superview, `.zero` produces a view that is never asked to draw, where
    /// the screen's own bounds are at least a usable guess until ``didMoveToSuperview()`` gives
    /// the real answer moments later.
    internal override func updateFrame() {
        frame = superview?.bounds ?? UIScreen.main.bounds
        refreshGuides()
    }

    /// Recomputes ``lines`` and ``labels`` for the current `bounds` and window, and asks for a
    /// fresh ``draw(_:)``.
    ///
    /// The one place ``lastHandledBounds`` is written, so every caller — ``updateFrame()``,
    /// ``layoutSubviews()`` — leaves it in step with what was actually just computed.
    private func refreshGuides() {
        lastHandledBounds = bounds
        layoutLabels()
        setNeedsDisplay()
    }

    // MARK: - Line Placement

    /// Where every guide runs, for a given set of insets.
    ///
    /// Static and pure so the rules are testable: an overlay's `draw(_:)` cannot be inspected by
    /// a test, so anything decided inside it is decided unchecked.
    ///
    /// A zero inset draws nothing, and so does an inset that *rounds* to zero: a sub-point inset
    /// such as `0.33` passes a raw `> 0` check yet would still label itself `"0 pt"` flush
    /// against the screen edge — exactly the noise the zero-inset rule exists to prevent. The
    /// guard below is therefore written against the rounded value, matching
    /// ``GuideLine/roundedValue``, which is what the label actually reads.
    ///
    /// - Parameters:
    ///   - safeArea: The window's safe-area insets.
    ///   - margins: The root view's layout margins.
    ///   - bounds: The overlay's bounds.
    /// - Returns: The lines to stroke, safe-area lines first.
    static func guideLines(safeArea: UIEdgeInsets,
                           margins: UIEdgeInsets,
                           in bounds: CGRect) -> [GuideLine] {
        var lines: [GuideLine] = []

        func add(_ inset: CGFloat, _ kind: GuideLine.Kind, _ make: (CGFloat) -> (CGPoint, CGPoint)) {
            guard inset.rounded() > 0 else { return }
            let (start, end) = make(inset)
            lines.append(GuideLine(start: start, end: end, value: inset, kind: kind))
        }

        for (insets, kind) in [(safeArea, GuideLine.Kind.safeArea), (margins, .margin)] {
            add(insets.top, kind) { (CGPoint(x: bounds.minX, y: $0), CGPoint(x: bounds.maxX, y: $0)) }
            add(insets.bottom, kind) { (CGPoint(x: bounds.minX, y: bounds.maxY - $0),
                                       CGPoint(x: bounds.maxX, y: bounds.maxY - $0)) }
            add(insets.left, kind) { (CGPoint(x: $0, y: bounds.minY), CGPoint(x: $0, y: bounds.maxY)) }
            add(insets.right, kind) { (CGPoint(x: bounds.maxX - $0, y: bounds.minY),
                                      CGPoint(x: bounds.maxX - $0, y: bounds.maxY)) }
        }

        return lines
    }

    // MARK: - Labels

    /// Where a line's label should sit, clamped inside `bounds`.
    ///
    /// A thin forward to ``LayoutRulerGeometry/labelOrigin(midpoint:labelSize:in:margin:)`` — the
    /// same placement rule the layout ruler uses to keep its own measurement label inside the
    /// screen — rather than a second clamping rule written here. A label simply centred on its
    /// line, as the first version of this view did, is cut off by the screen edge whenever the line
    /// itself is close to one; reusing the ruler's rule means that failure mode has exactly one fix
    /// in the codebase rather than two that could drift apart — including the margin, which is
    /// ``LabelMargin`` here and ``LayoutRulerOverlayView/ReadoutMargin`` there, both taken by the
    /// same clamp rather than by a second one per caller. Static and pure, like
    /// ``guideLines(safeArea:margins:in:)``, so the integration itself — not just the geometry
    /// underneath it — is directly testable.
    ///
    /// - Parameters:
    ///   - line: The guide the label belongs to; its ``GuideLine/labelMidpoint`` is what gets
    ///     clamped.
    ///   - labelSize: The label's rendered, padded size.
    ///   - bounds: The overlay's size.
    /// - Returns: The label's frame, guaranteed to stay within `bounds` and no closer than
    ///   ``LabelMargin`` to any of its edges.
    static func labelFrame(for line: GuideLine, labelSize: CGSize, in bounds: CGSize) -> CGRect {
        let origin = LayoutRulerGeometry.labelOrigin(midpoint: line.labelMidpoint,
                                                     labelSize: labelSize,
                                                     in: bounds,
                                                     margin: LabelMargin)
        return CGRect(origin: origin, size: labelSize)
    }

    /// Rebuilds ``labels`` for the current window and `bounds`, and refreshes ``lines`` to match.
    ///
    /// Reads the safe-area insets and layout margins from `window` rather than caching them,
    /// because both can change without this view's own `bounds` changing — a keyboard or a sheet
    /// can shift a root view's margins independently of this view's size.
    private func layoutLabels() {
        labels.forEach { $0.removeFromSuperview() }
        labels.removeAll()

        let currentLines = LayoutGuidesView.guideLines(
            safeArea: window?.safeAreaInsets ?? .zero,
            margins: window?.rootViewController?.view.layoutMargins ?? .zero,
            in: bounds
        )
        lines = currentLines

        for line in currentLines {
            let label = UILabel()
            label.font = .systemFont(ofSize: LayoutGuidesView.LabelFontSize)
            label.textColor = .white
            label.backgroundColor = line.kind.colour
            label.textAlignment = .center
            label.text = localized("\(line.roundedValue) pt")
            label.sizeToFit()

            let paddedSize = CGSize(width: label.frame.width + LayoutGuidesView.LabelHorizontalPadding * 2,
                                    height: label.frame.height)
            label.frame = LayoutGuidesView.labelFrame(for: line, labelSize: paddedSize, in: bounds.size)

            addSubview(label)
            labels.append(label)
        }
    }

    // MARK: - Drawing

    /// Strokes one line per guide in ``lines`` — safe-area lines solid, margin lines dashed.
    ///
    /// Only strokes: label construction and placement happen in ``layoutLabels()``, not here —
    /// see ``labels``'s own documentation for why mutating the view hierarchy moved out of the
    /// render pass.
    ///
    /// - Parameter rect: The portion of the view's bounds that needs to be updated.
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for line in lines {
            context.setStrokeColor(line.kind.colour.cgColor)
            context.setLineWidth(LayoutGuidesView.LineWidth)
            context.setLineDash(phase: 0, lengths: line.kind.isDashed ? LayoutGuidesView.MarginDashPattern : [])
            context.move(to: line.start)
            context.addLine(to: line.end)
            context.strokePath()
        }
    }
}
#endif
