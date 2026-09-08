//
//  LayoutRuler.swift
//  Scyther
//
//  Created by Brandon Stillitano on 9/9/2026.
//

#if !os(macOS)
import UIKit

/// The layout ruler's session state, and the one function that turns two points into an answer.
///
/// Nothing here is persisted, unlike ``LayoutGuides``. A ruler that survived a relaunch would be a
/// debugging tool the developer has to remember to switch off — and it is the one overlay in
/// Scyther that consumes every touch on the screen, so forgetting it looks like the app has
/// frozen. The mode is not persisted either: snap is the answer to the question the ruler exists
/// for, and a session with a ruler in it is measured in minutes.
///
/// This type has no `AppEnvironment` check of its own, on purpose, for the reason ``LayoutGuides``
/// does not: safety is inherited from ``InterfaceToolkit/start()``, which is only reached from
/// `Scyther.start()` — gated on `AppEnvironment.isAppStore`/`allowProductionBuilds`. One gate,
/// inherited, is the whole toolkit's convention, and a second local one is a second answer that
/// can drift from the first.
///
/// ## Topics
///
/// ### Getting the Shared Instance
/// - ``instance``
///
/// ### Session State
/// - ``isActive``
/// - ``snaps``
///
/// ### Measuring
/// - ``measurement(from:to:in:snapping:)``
/// - ``Measurement``
@MainActor
internal final class LayoutRuler: Sendable {
    /// The shared instance. The menu row and ``InterfaceToolkit`` both read and write this one.
    static let instance = LayoutRuler()

    /// Private init to stop re-initialisation and allow singleton creation.
    private init() { }

    /// Whether the ruler's overlay is on screen and taking touches.
    ///
    /// Pushes straight to ``InterfaceToolkit/showLayoutRuler()`` on change, the way
    /// ``LayoutGuides/enabled`` pushes to ``InterfaceToolkit/showLayoutGuides()``, so that setting
    /// this from anywhere — the menu row, the overlay's own Done button — shows or hides the
    /// overlay rather than only recording an intention. Guarded on an actual change so that
    /// ``InterfaceToolkit/showLayoutRuler()`` setting nothing new cannot loop back through here.
    ///
    /// Not persisted. See this type's own documentation for why.
    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            InterfaceToolkit.instance.showLayoutRuler()
        }
    }

    /// Whether each endpoint attaches to the nearest edge of the view beneath it.
    ///
    /// `true` by default, because the question the ruler exists to answer is "is this the 16
    /// points I specified", and a number that depends on how steady a thumb was cannot answer it.
    /// Free mode is for the cases with no edge to snap to: into whitespace, or to a point inside
    /// an image.
    ///
    /// Deliberately without a push of its own. Nothing needs redrawing when the mode changes: the
    /// mode is read at the start of the *next* drag, and re-snapping the measurement already on
    /// screen would silently rewrite an answer the developer is still reading.
    var snaps: Bool = true

    // MARK: - Measuring

    /// Measures between two points in `root`'s coordinate space.
    ///
    /// Static, and taking its root view as a parameter rather than reaching for the key window,
    /// so the whole rule is reachable from a test: a drag cannot be driven by one, but the thing
    /// the drag computes can be, given any view hierarchy at all.
    ///
    /// Composes the two pure pieces this feature is built from and adds no arithmetic of its own —
    /// ``ViewProbe`` decides what is under a point, ``LayoutRulerGeometry`` decides where the edge
    /// is and how far apart the results are.
    ///
    /// - Parameters:
    ///   - start: Where the drag began, in `root`'s coordinate space.
    ///   - end: Where the finger is now, in the same space.
    ///   - root: The hierarchy to probe. The overlay passes its window.
    ///   - snapping: Whether to attach each endpoint to the view beneath it.
    /// - Returns: The measurement, or `nil` when the two points are closer together than
    ///   ``LayoutRulerGeometry/minimumMeasurableDistance`` — a tap, which must not produce a
    ///   `0 pt` reading that looks like an answer.
    static func measurement(from start: CGPoint,
                            to end: CGPoint,
                            in root: UIView,
                            snapping: Bool) -> Measurement? {
        let first = resolve(start, in: root, snapping: snapping)
        let second = resolve(end, in: root, snapping: snapping)

        let distance = LayoutRulerGeometry.distance(from: first.point, to: second.point)
        guard distance >= LayoutRulerGeometry.minimumMeasurableDistance else { return nil }

        return Measurement(start: first.point,
                           end: second.point,
                           distance: distance,
                           startDescription: first.description,
                           endDescription: second.description)
    }

    /// Turns one raw point into the point that will actually be measured, and the name of what it
    /// attached to.
    ///
    /// The name is built from the view's class and the edge — `UILabel.bottom` — because that is
    /// the only honest name available. A view has no identifier a developer chose: `restorationIdentifier`
    /// is nearly always `nil`, and an accessibility label is both frequently absent and *forbidden*
    /// on this path — reading one makes UIAccessibility compute a subtree recursively, which is
    /// what hung the app when the accessibility audit shipped, and this runs once per touch-move
    /// rather than once per navigation (see ``ViewProbe``). Naming the class and the edge tells the
    /// developer what the measurement attached to, which is the question a readout of a bare number
    /// leaves open; anything richer is the view hierarchy inspector's job, and that is deliberately
    /// a separate feature.
    ///
    /// A point with nothing under it keeps its own coordinates and is named `nil`. Reporting a
    /// snap that did not happen would be worse than reporting no snap.
    ///
    /// "Nothing under it" is rarer than it sounds, and deliberately so. The probe skips Scyther's
    /// own interface but does not stop there — it keeps descending and finds whatever of the app
    /// is *underneath*, which is what makes the ruler usable at all: its own overlay covers the
    /// entire screen while it is active, and a rule that gave up at the first Scyther-owned view
    /// would snap to nothing, anywhere, ever. So a point over the ruler's own control measures the
    /// app beneath the control. The fallback is for a point genuinely over nothing: off the
    /// window, or on a screen whose every candidate is hidden or transparent.
    ///
    /// - Parameters:
    ///   - point: The raw point, in `root`'s coordinate space.
    ///   - root: The hierarchy to probe.
    ///   - snapping: Whether to attach to a view at all.
    /// - Returns: The point to measure and the name of what it attached to, if anything.
    private static func resolve(_ point: CGPoint,
                                in root: UIView,
                                snapping: Bool) -> (point: CGPoint, description: String?) {
        guard snapping, let view = ViewProbe.view(at: point, in: root) else { return (point, nil) }

        // The view's own bounds converted into `root`'s space, rather than its `frame`: `frame` is
        // stated in its *superview's* space, so it is the right rectangle only when the superview
        // happens to be `root`. `convert(_:from:)` walks whatever chain is actually between them,
        // and answers correctly when the probe returns `root` itself.
        let frame = root.convert(view.bounds, from: view)
        let snapped = LayoutRulerGeometry.snapped(point, to: frame)
        return (snapped.point, "\(type(of: view)).\(snapped.edge.rawValue)")
    }
}

// MARK: - Measurement

extension LayoutRuler {
    /// One completed measurement: where it runs, how long it is, and what it attached to.
    ///
    /// Nested inside ``LayoutRuler`` rather than declared at the module's top level, and that is
    /// not a stylistic choice: Foundation exports a generic `Measurement<UnitType>`, and a
    /// non-generic `Measurement` at Scyther's own module scope would shadow it for every file in
    /// the module — including ones that have nothing to do with the ruler and would fail to
    /// compile against a type they never asked for.
    ///
    /// A value type, so a measurement is a snapshot of an answer rather than something that keeps
    /// tracking the screen. That is the behaviour the spec asks for: content scrolling under a
    /// finished measurement leaves it where it was drawn, because a measurement that quietly
    /// followed the layout would silently become wrong.
    struct Measurement: Equatable, Sendable {
        /// Where the measurement starts, in the space it was measured in — the overlay's window.
        let start: CGPoint

        /// Where it ends, in the same space.
        let end: CGPoint

        /// The straight-line distance between ``start`` and ``end``, in points.
        ///
        /// Stored rather than recomputed from the two points, so that what the readout says and
        /// what the line draws can never disagree.
        let distance: CGFloat

        /// What ``start`` attached to — `"UILabel.bottom"` — or `nil` in free mode and wherever
        /// the probe found nothing.
        let startDescription: String?

        /// What ``end`` attached to, or `nil` for the same reasons.
        let endDescription: String?
    }
}
#endif
