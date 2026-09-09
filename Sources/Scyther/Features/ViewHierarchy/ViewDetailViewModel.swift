//
//  ViewDetailViewModel.swift
//  Scyther
//

#if !os(macOS)
import SwiftUI
import UIKit

/// What the inspector says about one selected view.
///
/// Everything here is read **once**, in ``onFirstAppear()``, and never recomputed. Two reasons,
/// and both matter:
///
/// - The thumbnail is rasterisation, the one expensive thing this feature does. A computed
///   property would re-render it on every SwiftUI re-render — a scroll, a rotation, a
///   `@Published` change elsewhere on the page.
/// - A snapshot that quietly re-read the live view would stop being a snapshot. The tree the
///   developer navigated and the fields they are reading would then disagree about the same
///   moment, which is the one thing a debugging tool must not do.
///
/// Fields whose value can only come from the live view are **omitted** when that view has been
/// deallocated since the walk, rather than shown blank. A row reading `Bounds —` says the view
/// has no bounds; no row at all says nobody asked, which is the truth.
///
/// ## Two moments, and which field belongs to which
///
/// `Frame (in window)` and `Text content` come from the ``ViewNode``, so they are what the walk
/// recorded; everything else is read from the live view when the page opens. The two differ when a
/// layout pass has run in between, and that is the right way round rather than an oversight:
/// the window-space frame is only reconstructible during the walk, and it is the frame the tree
/// was searched and drawn by, so re-reading it would make this page disagree with the row that
/// got the reader here. Nothing is read twice, so within each of the two moments the page is
/// consistent.
@MainActor
final class ViewDetailViewModel: ViewModel {
    /// One labelled value on the page.
    ///
    /// `id` is a stable, hand-written token — `"frame"`, `"alpha"`, `"controller"` — rather than
    /// the label, which is localised, or an index, which moves when a field is omitted. Two
    /// fields sharing an id would collapse into one row in a `List`.
    struct DetailField: Identifiable, Equatable {
        /// A stable token, distinct across every section of the page.
        let id: String

        /// The localised label shown on the leading side of the row.
        let label: String

        /// The value shown on the trailing side.
        let value: String
    }

    /// The node this page describes.
    let node: ViewNode

    /// The window space every frame on the page is measured in, for the position map.
    let windowBounds: CGRect

    /// The snapshot the node came from, holding the weak bridge back to the live view.
    private let snapshot: ViewHierarchySnapshot

    /// What there is to show for the view, decided once in ``onFirstAppear()``, or `nil` until
    /// it has been asked.
    ///
    /// Optional because every case of ``ViewThumbnailRenderer/Thumbnail`` is a positive claim
    /// about the view, and there is no honest one to start with. `.onFirstAppear` is a `.task`,
    /// which runs *after* the first render, so a non-optional property defaulting to
    /// `.unavailable` would flash "This view no longer exists" for a frame at a view that is
    /// perfectly alive. `nil` says only that nobody has asked yet — one property, so the answer
    /// and whether there is an answer cannot come to disagree.
    @Published private(set) var thumbnail: ViewThumbnailRenderer.Thumbnail?

    /// Frame, bounds, centre and the insets around them.
    @Published private(set) var geometry: [DetailField] = []

    /// Alpha, visibility, background, corners and any text the view draws.
    @Published private(set) var appearance: [DetailField] = []

    /// The owning controller and the responder chain above the view.
    @Published private(set) var context: [DetailField] = []

    /// Whether the view takes touches, and its tag.
    @Published private(set) var behaviour: [DetailField] = []

    /// The frame, formatted, for the position map's accessibility value.
    ///
    /// Computed rather than stored because it is string formatting of a value the node already
    /// holds — the ban on computed properties here is about rasterisation, not arithmetic — and
    /// because a drawing needs a value to read out before ``onFirstAppear()`` has run.
    var frameSummary: String {
        Self.describe(node.frameInWindow)
    }

    /// Creates the page's model.
    ///
    /// - Parameters:
    ///   - node: The selected node.
    ///   - snapshot: The snapshot it came from, used to reach the live view.
    ///   - windowBounds: The window space the node's frame is measured in.
    init(node: ViewNode, snapshot: ViewHierarchySnapshot, windowBounds: CGRect) {
        self.node = node
        self.snapshot = snapshot
        self.windowBounds = windowBounds
        super.init()
    }

    /// Reads everything the page shows, once.
    ///
    /// The live view is resolved a single time and handed to each section, so every field that
    /// comes from the live view describes the same moment even if the view is deallocated
    /// part-way through the method. `Frame` and `Text content` come from the node instead, and
    /// so describe the walk — see the type's own documentation for why that is the right way
    /// round.
    override func onFirstAppear() async {
        await super.onFirstAppear()

        let view = snapshot.view(for: node.id)

        // `node.isHidden`, never `view.isHidden`: the node's flag already folds in an effective
        // alpha at or below 0.01 and invisibility inherited from an ancestor, and a transparent
        // view would otherwise rasterise to a blank image reported as a successful thumbnail.
        thumbnail = ViewThumbnailRenderer.thumbnail(of: view,
                                                    isHidden: node.isHidden,
                                                    isZeroSize: node.isZeroSize)
        geometry = geometryFields(for: view)
        appearance = appearanceFields(for: view)
        context = contextFields(for: view)
        behaviour = behaviourFields(for: view)
    }

    // MARK: - Sections

    /// Frame, and — while the view exists — bounds, centre and the insets around it.
    ///
    /// The frame comes from the node, so it is the frame the tree was walked with rather than
    /// whatever the view has been laid out to since. It is the one geometry field a deallocated
    /// view still has an honest answer for.
    ///
    /// - Parameter view: The live view, or `nil`.
    /// - Returns: The section's fields, in reading order.
    private func geometryFields(for view: UIView?) -> [DetailField] {
        // Labelled *in window*, not simply "Frame": `UIView.frame` is stated in the superview's
        // coordinate space, so a bare "Frame" beside a nested view's window-space rect asserts
        // something false about every view but a window's own children.
        var fields = [DetailField(id: "frame",
                                  label: localized("Frame (in window)"),
                                  value: Self.describe(node.frameInWindow))]
        guard let view else { return fields }

        fields.append(DetailField(id: "bounds",
                                  label: localized("Bounds"),
                                  value: Self.describe(view.bounds)))
        fields.append(DetailField(id: "centre",
                                  label: localized("Centre"),
                                  value: Self.describe(view.center)))
        fields.append(DetailField(id: "safeArea",
                                  label: localized("Safe area"),
                                  value: Self.describe(view.safeAreaInsets)))
        fields.append(DetailField(id: "layoutMargins",
                                  label: localized("Layout margins"),
                                  value: Self.describe(view.layoutMargins)))
        return fields
    }

    /// Alpha, visibility, background, corners, and the text a text-carrying view draws.
    ///
    /// Visibility is reported from ``ViewNode/isHidden`` rather than `view.isHidden`, which is
    /// why the row is labelled *Effectively hidden*: it is the same flag the thumbnail trusted,
    /// so the page cannot say "not hidden" beside a picture that says "this view is hidden". The
    /// view's own `alpha` sits immediately above it, which is where a reader looks for the
    /// difference.
    ///
    /// - Parameter view: The live view, or `nil`.
    /// - Returns: The section's fields, in reading order.
    private func appearanceFields(for view: UIView?) -> [DetailField] {
        var fields: [DetailField] = []
        if let view {
            fields.append(DetailField(id: "alpha",
                                      label: localized("Alpha"),
                                      value: Self.describe(view.alpha)))
        }
        fields.append(DetailField(id: "hidden",
                                  label: localized("Effectively hidden"),
                                  value: Self.describe(node.isHidden)))
        if let text = node.text, !text.isEmpty {
            fields.append(DetailField(id: "text",
                                      label: localized("Text content"),
                                      value: text))
        }
        guard let view else { return fields }

        fields.append(DetailField(id: "background",
                                  label: localized("Background"),
                                  value: view.backgroundColor.map { Self.describe($0) } ?? localized("None")))
        fields.append(DetailField(id: "cornerRadius",
                                  label: localized("Corner radius"),
                                  value: Self.describe(view.layer.cornerRadius)))
        fields.append(DetailField(id: "clipsToBounds",
                                  label: localized("Clips to bounds"),
                                  value: Self.describe(view.clipsToBounds)))
        fields.append(DetailField(id: "contentMode",
                                  label: localized("Content mode"),
                                  value: Self.describe(view.contentMode)))
        let textCarrying = TextCarryingView(view)
        if let font = textCarrying?.font {
            fields.append(DetailField(id: "font",
                                      label: localized("Font"),
                                      value: Self.describe(font)))
        }
        if let colour = textCarrying?.textColour {
            fields.append(DetailField(id: "textColour",
                                      label: localized("Text colour"),
                                      value: Self.describe(colour)))
        }
        return fields
    }

    /// The owning controller and the responder chain above the view.
    ///
    /// Every field here needs the live view, so a deallocated one yields an empty section rather
    /// than a chain of dashes.
    ///
    /// - Parameter view: The live view, or `nil`.
    /// - Returns: The section's fields, in reading order.
    private func contextFields(for view: UIView?) -> [DetailField] {
        guard let view else { return [] }

        var fields: [DetailField] = []
        if let controller = ViewContext.owningController(of: view) {
            fields.append(DetailField(id: "controller",
                                      label: localized("Controller"),
                                      value: String(describing: type(of: controller))))
        }
        fields.append(DetailField(id: "responderChain",
                                  label: localized("Responder chain"),
                                  value: ViewContext.responderChain(from: view).joined(separator: " → ")))
        fields.append(DetailField(id: "firstResponder",
                                  label: localized("First responder"),
                                  value: Self.describe(ViewContext.isFirstResponder(view))))
        return fields
    }

    /// Whether the view takes touches, and its tag.
    ///
    /// - Parameter view: The live view, or `nil`.
    /// - Returns: The section's fields, in reading order.
    private func behaviourFields(for view: UIView?) -> [DetailField] {
        guard let view else { return [] }

        return [DetailField(id: "interaction",
                            label: localized("Interaction"),
                            value: Self.describe(view.isUserInteractionEnabled)),
                DetailField(id: "tag",
                            label: localized("Tag"),
                            value: String(view.tag))]
    }

    // MARK: - Formatting

    /// A measurement, with no trailing zeros.
    ///
    /// `%g` rather than a fixed number of decimal places, so a whole number reads `16` and a
    /// fractional one keeps the fraction that matters — a half-point offset is a real layout
    /// answer, and `16.0` beside `16.5` is noise around it.
    ///
    /// - Parameter value: The measurement.
    /// - Returns: Its shortest faithful rendering.
    private static func describe(_ value: CGFloat) -> String {
        String(format: "%g", value)
    }

    /// A rect, as `x, y, width × height`.
    ///
    /// `×` rather than `x`, because `x` is also the name of the first number in the same string.
    ///
    /// - Parameter rect: The rect.
    /// - Returns: Its rendering.
    private static func describe(_ rect: CGRect) -> String {
        "\(describe(rect.origin.x)), \(describe(rect.origin.y)), \(describe(rect.width)) × \(describe(rect.height))"
    }

    /// A point, as `x, y`.
    ///
    /// - Parameter point: The point.
    /// - Returns: Its rendering.
    private static func describe(_ point: CGPoint) -> String {
        "\(describe(point.x)), \(describe(point.y))"
    }

    /// Insets, in `UIEdgeInsets`' own order: top, left, bottom, right.
    ///
    /// - Parameter insets: The insets.
    /// - Returns: Their rendering.
    private static func describe(_ insets: UIEdgeInsets) -> String {
        "\(describe(insets.top)), \(describe(insets.left)), \(describe(insets.bottom)), \(describe(insets.right))"
    }

    /// A flag, as the catalogue's shared `Yes` / `No`.
    ///
    /// Both keys belong to another fragment and are called rather than redefined: a key lives in
    /// one fragment but resolves from the single flat catalogue, and a second definition is a
    /// build failure.
    ///
    /// - Parameter flag: The flag.
    /// - Returns: Its localised rendering.
    private static func describe(_ flag: Bool) -> String {
        flag ? localized("Yes") : localized("No")
    }

    /// A colour, as `#RRGGBBAA`, clamped to sRGB.
    ///
    /// `getRed(_:green:blue:alpha:)` rather than ``UIKit/UIColor/hexCode(withAlpha:)``, which
    /// reads `cgColor.components` and so returns `nil` for a colour in a grayscale space —
    /// `.white` and `.black`, two of the commonest backgrounds there are. A colour that resolves
    /// to no RGB at all, such as a pattern, falls back to its own description, which at least
    /// names it.
    ///
    /// The components are **clamped**, because `getRed` reports a wide-gamut colour in *extended*
    /// sRGB, where a component may be negative or above one. `#RRGGBBAA` cannot express that at
    /// all, so clamping is the honest rendering of it; leaving it unclamped is not, because
    /// `%02lX` prints a negative `Int` as a sixteen-digit two's-complement word and the row then
    /// reads `#116FFFFFFFFFFFFFFEBFF…` instead of a colour.
    ///
    /// - Parameter colour: The colour.
    /// - Returns: Its rendering.
    private static func describe(_ colour: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return String(describing: colour)
        }
        return String(format: "#%02lX%02lX%02lX%02lX",
                      byte(red), byte(green), byte(blue), byte(alpha))
    }

    /// One colour component as an sRGB byte.
    ///
    /// - Parameter component: The component, possibly outside `0...1` for a wide-gamut colour.
    /// - Returns: The component clamped to `0...1` and scaled to `0...255`.
    private static func byte(_ component: CGFloat) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }

    /// A font, as its PostScript name and point size.
    ///
    /// - Parameter font: The font.
    /// - Returns: Its rendering.
    private static func describe(_ font: UIFont) -> String {
        "\(font.fontName) \(describe(font.pointSize))"
    }

    /// A content mode, under its UIKit name.
    ///
    /// Left in English on purpose: these are API identifiers, in the same class as the class
    /// names elsewhere on the page, and translating `scaleAspectFit` would make it harder to
    /// match against the code being debugged rather than easier.
    ///
    /// - Parameter mode: The mode.
    /// - Returns: Its UIKit case name.
    private static func describe(_ mode: UIView.ContentMode) -> String {
        switch mode {
        case .scaleToFill: return "scaleToFill"
        case .scaleAspectFit: return "scaleAspectFit"
        case .scaleAspectFill: return "scaleAspectFill"
        case .redraw: return "redraw"
        case .center: return "center"
        case .top: return "top"
        case .bottom: return "bottom"
        case .left: return "left"
        case .right: return "right"
        case .topLeft: return "topLeft"
        case .topRight: return "topRight"
        case .bottomLeft: return "bottomLeft"
        case .bottomRight: return "bottomRight"
        @unknown default: return String(mode.rawValue)
        }
    }
}
#endif
