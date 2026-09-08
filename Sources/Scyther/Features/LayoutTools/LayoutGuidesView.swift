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
    /// What the line represents, which decides its colour in ``LayoutGuidesView/draw(_:)``.
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

    /// The inset this line marks, in points — also what its label reads.
    let value: CGFloat

    /// Whether this is a safe-area line or a layout-margin line.
    let kind: Kind
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
}

/// Draws the key window's safe-area insets and layout margins.
///
/// A `TopLevelView` like ``GridOverlayView``: no touches, no state beyond its setting, redrawn
/// on ``updateFrame()``. Unlike ``GridOverlayView``, it holds no configuration of its own —
/// there is no size or colour to pick — so everything it draws is read fresh from the window on
/// every ``draw(_:)``.
internal class LayoutGuidesView: TopLevelView {
    // MARK: - Static Data

    /// Width, in points, of every stroked guide line.
    static var LineWidth: CGFloat = 1.0

    /// Font size for each line's `"N pt"` label.
    static var LabelFontSize: CGFloat = 9.0

    /// Horizontal padding inside a label, on each side of its text.
    static var LabelHorizontalPadding: CGFloat = 4.0

    // MARK: - UI Elements

    /// The labels drawn for the current set of lines, torn down and rebuilt on every
    /// ``draw(_:)`` because the number of lines varies with how many insets are non-zero — see
    /// ``guideLines(safeArea:margins:in:)``. A fixed pool, the way ``GridOverlayView`` keeps two
    /// permanent labels, does not fit a count that can be anywhere from zero to eight.
    private var labels: [UILabel] = []

    // MARK: - Init

    /// Initialises the overlay, non-interactive and sized to its eventual superview.
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

    /// Configures the view to take no touches and draw nothing of its own until ``draw(_:)``
    /// strokes the current guides.
    ///
    /// `accessibilityElementsHidden` is set here, and not merely inherited from
    /// `isUserInteractionEnabled = false`, because a screen reader can still describe a
    /// non-interactive view's frame — a guide line has nothing to say to VoiceOver, and every
    /// other overlay in Scyther keeps quiet the same way.
    private func setupUI() {
        updateFrame()
        isUserInteractionEnabled = false
        isOpaque = false
        accessibilityElementsHidden = true
    }

    /// Resizes the overlay to match its superview — ``InterfaceToolkit/topLevelViewsWrapper`` —
    /// and asks for a fresh ``draw(_:)``.
    ///
    /// Bound to the superview rather than to `UIScreen.main.bounds`, as ``GridOverlayView``
    /// is: the superview is already kept in step with the screen (see
    /// `TopLevelViewsWrapper.updateFrame()`), and reading it here means this view's bounds are
    /// never a frame behind its own coordinate space — which matters more here than for the
    /// grid, since ``guideLines(safeArea:margins:in:)`` measures every line from `bounds`.
    internal override func updateFrame() {
        frame = superview?.bounds ?? .zero
        setNeedsDisplay()
    }

    // MARK: - Line Placement

    /// Where every guide runs, for a given set of insets.
    ///
    /// Static and pure so the rules are testable: an overlay's `draw(_:)` cannot be inspected by
    /// a test, so anything decided inside it is decided unchecked.
    ///
    /// A zero inset draws nothing. A line labelled `0 pt` flush against the screen edge is noise,
    /// and on a device with no home indicator the bottom inset genuinely is zero.
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
            guard inset > 0 else { return }
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

    // MARK: - Drawing

    /// Strokes one line per non-zero inset and labels each with its measurement.
    ///
    /// Reads the safe-area insets and layout margins from `window` rather than caching them,
    /// because both can change without this view's own frame changing — a rotation moves the
    /// home indicator's inset, and a keyboard or a sheet can shift a root view's margins — and
    /// there is no cheaper hook than redrawing on demand for a view that is otherwise idle.
    ///
    /// Labels are plain `UILabel`s, positioned and added directly inside this method the way
    /// ``GridOverlayView/draw(_:)`` repositions its own two labels — except here the *count* of
    /// labels varies with how many insets are non-zero, so the previous pass's labels are torn
    /// down first rather than merely repositioned.
    ///
    /// - Parameter rect: The portion of the view's bounds that needs to be updated.
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        labels.forEach { $0.removeFromSuperview() }
        labels.removeAll()

        let lines = LayoutGuidesView.guideLines(
            safeArea: window?.safeAreaInsets ?? .zero,
            margins: window?.rootViewController?.view.layoutMargins ?? .zero,
            in: bounds
        )

        for line in lines {
            context.setStrokeColor(line.kind.colour.cgColor)
            context.setLineWidth(LayoutGuidesView.LineWidth)
            context.move(to: line.start)
            context.addLine(to: line.end)
            context.strokePath()

            let label = UILabel()
            label.font = .systemFont(ofSize: LayoutGuidesView.LabelFontSize)
            label.textColor = .white
            label.backgroundColor = line.kind.colour
            label.textAlignment = .center
            label.text = localized("\(Int(line.value)) pt")
            label.sizeToFit()
            label.frame = label.frame.insetBy(dx: -LayoutGuidesView.LabelHorizontalPadding, dy: 0)
            label.center = CGPoint(x: (line.start.x + line.end.x) / 2,
                                   y: (line.start.y + line.end.y) / 2)
            addSubview(label)
            labels.append(label)
        }
    }
}
#endif
