import UIKit

/// Facts about a node that only some kinds of node can supply.
///
/// Two of the audit's rules need to know something the accessibility tree does not carry: what
/// point size a piece of text is drawn at, and whether an element reads a value when it has no
/// label. A `UILabel` can answer both; a synthetic `UIAccessibilityElement` can answer neither,
/// and neither can a test double unless it opts in.
///
/// Kept as a separate protocol rather than folded into ``AuditNode`` precisely because of that
/// asymmetry: ``AuditNode`` is the set of questions *every* node can answer, and widening it
/// with questions most nodes must answer `nil` to would push the "I don't know" case into every
/// adapter instead of into the one rule that has to handle it. A rule asks for this with `as?`
/// and has to have an answer ready for `nil`, which is the honest shape — see
/// ``AccessibilityAuditor/contrastThreshold(for:)``, which stays at the strict threshold rather
/// than guessing when no size can be read.
@MainActor
protocol AuditNodeDetails {
    /// The point size of the text the node draws, or `nil` when it draws none or cannot say.
    var auditFontPointSize: CGFloat? { get }

    /// Whether that text is bold, which lowers WCAG's large-text threshold.
    var auditFontIsBold: Bool { get }

    /// Whether the node actually draws text, as opposed to having a name for one.
    var auditDrawsText: Bool { get }

    /// What VoiceOver would read as the node's value, if anything.
    var auditAccessibilityValue: String? { get }
}

extension AuditNodeDetails {
    /// Nothing known, which is the right answer for any node that has not overridden these.
    var auditFontPointSize: CGFloat? { nil }

    /// Nothing known, so not bold.
    var auditFontIsBold: Bool { false }

    /// Nothing known, so no claim that the node draws text.
    var auditDrawsText: Bool { false }

    /// Nothing known, so no value.
    var auditAccessibilityValue: String? { nil }
}

extension UIView: AuditNodeDetails {
    /// The font of the view's own text, for the handful of UIKit views that draw text directly.
    ///
    /// A `UIButton`'s title label rather than the button, because that is where the font lives.
    /// Anything else — a container, a custom view drawing text itself, a SwiftUI backing view —
    /// reports nothing rather than a guess.
    private var auditFont: UIFont? {
        if let label = self as? UILabel { return label.font }
        if let field = self as? UITextField { return field.font }
        if let textView = self as? UITextView { return textView.font }
        if let button = self as? UIButton { return button.titleLabel?.font }
        return nil
    }

    /// The point size the view draws its text at, already scaled by Dynamic Type — which is what
    /// WCAG's rule is about, since the size on screen is the size the reader reads.
    public var auditFontPointSize: CGFloat? { auditFont?.pointSize }

    /// Whether the resolved font is bold, read from the descriptor's symbolic traits so a bold
    /// text style counts as well as an explicitly bold face.
    public var auditFontIsBold: Bool {
        auditFont?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
    }

    /// Whether the view has text in it right now.
    ///
    /// An icon-only `UIButton` has a name and no title, which is exactly the distinction the
    /// contrast threshold turns on: WCAG grades text at 4.5:1 and non-text content at 3:1, and
    /// "has an accessibility label" is evidence of the former only if you confuse a name with
    /// content.
    public var auditDrawsText: Bool {
        if let label = self as? UILabel { return label.text?.isEmpty == false }
        if let field = self as? UITextField { return field.text?.isEmpty == false }
        if let textView = self as? UITextView { return textView.text?.isEmpty == false }
        if let button = self as? UIButton { return button.currentTitle?.isEmpty == false }
        return false
    }

    /// Direct read of `accessibilityValue`.
    public var auditAccessibilityValue: String? { accessibilityValue }
}

/// Walks a tree of ``AuditNode`` and reports what is wrong with it.
///
/// Pure with respect to UIKit: it is handed a root and returns findings, so every rule in it can
/// be tested against a tree of doubles with no window, no simulator UI and no timing.
@MainActor
struct AccessibilityAuditor {
    /// How deep the walk goes before it gives up.
    ///
    /// A hierarchy deeper than this is either pathological or cyclic, and hanging the app the
    /// developer is debugging is worse than an incomplete answer — as long as the answer says it
    /// is incomplete.
    static let maximumDepth = 100

    /// How many nodes the walk visits before it gives up, for the same reason.
    static let maximumNodes = 5000

    /// How long a whole pass is allowed to take before it gives up, in seconds.
    ///
    /// A cap measured in nodes only protects the developer from a walk that is *long*. It does
    /// nothing about a walk that is slow per node, which is the shape a real hierarchy takes when
    /// something below ``AuditNode/children`` turns out to cost more than a property read — and
    /// the walk runs on the main thread, inside the report screen's first appear, so a walk that
    /// takes seconds is a frozen app rather than a slow screen. A quarter of a second is about
    /// the longest the main thread can be held without a developer noticing, and a partial report
    /// that admits it is partial beats a complete one nobody waits for.
    ///
    /// It is a budget for the **pass**, not for the walk. The walk reads properties; the loop
    /// after it crops and rasterises a region of a window bitmap for every text element it was
    /// handed, up to ``maximumNodes`` of them, and that is by far the more expensive half. A
    /// deadline that expired only inside the walk bounded the cheap part and left the costly
    /// part to run for as long as it liked, which is the same defect the budget was added to
    /// fix — so the deadline is created once, at the top of the pass, and carried through both.
    static let budget: TimeInterval = 0.25

    /// Reads the current time, so a test can spend the budget deterministically.
    ///
    /// A wall-clock budget tested against the wall clock is a test that either sleeps or flakes.
    /// Taking the clock through a closure lets `AccessibilityAuditorWalkTests` drive it forward by
    /// hand, and costs production nothing: the default is `Date.init` itself.
    var now: () -> Date = Date.init

    /// Every element worth checking, in tree order.
    ///
    /// - Parameters:
    ///   - root: The node to walk from, usually the key window.
    ///   - deadline: When the walk must stop, shared with the rest of the pass. `nil` starts a
    ///     fresh ``budget`` from now, which is what a caller walking a tree on its own wants.
    /// - Returns: The elements found, and whether a cap stopped the walk before it finished.
    func collect(root: AuditNode, deadline: Date? = nil) -> (nodes: [AuditNode], didHitLimit: Bool) {
        var found: [AuditNode] = []
        var didHitLimit = false
        var visited = 0
        let deadline = deadline ?? now().addingTimeInterval(Self.budget)

        /// Walks the tree depth-first, counting every node visited to prevent pathological
        /// hierarchies of containers from bypassing the node cap, and enforcing the depth, node
        /// and time limits.
        ///
        /// "Every node visited" means every node the walk *touches*, which is why the counter sits
        /// above the skip guard rather than below it. A skipped node is not a free node: deciding
        /// to skip it costs an ownership walk up its responder chain and a frame conversion up its
        /// superview chain, which is most of what a node costs at all. Counting only the survivors
        /// let a container of 200,000 pooled, hidden or off-screen subviews — a cell cache, a
        /// pre-built calendar of hidden day cells, a reuse pool held as subviews — pay all of that
        /// and count as one, leaving only the wall clock to stop it. The developer was then told a
        /// perfectly ordinary screen was too big to audit, which is the failure the node cap exists
        /// to make legible rather than to hide.
        ///
        /// The root is not counted towards the visit budget — only its descendants are — so
        /// that the test's expectation of collecting exactly `maximumNodes` elements from a
        /// root and N children can be met without inflating the limit.
        ///
        /// The time check comes first and applies to the root too: unlike a node count, elapsed
        /// time is spent by whatever ``AuditNode/children`` costs rather than by how many nodes
        /// it hands back, so it has to be read before the next node is touched rather than after.
        /// All three limits raise the same `didHitLimit`, so the report has one thing to say —
        /// "this is partial" — and does not need to learn a second reason for it.
        func walk(_ node: AuditNode, depth: Int) {
            guard !didHitLimit else { return }
            guard now() < deadline else {
                didHitLimit = true
                return
            }
            guard depth <= Self.maximumDepth else {
                didHitLimit = true
                return
            }
            if depth > 0 {
                visited += 1
                guard visited <= Self.maximumNodes else {
                    didHitLimit = true
                    return
                }
            }

            guard !node.isScytherOwned, node.isVisible, !node.frameInWindow.isEmpty else { return }

            if node.isAccessibilityElementNode {
                found.append(node)
                return
            }

            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return (found, didHitLimit)
    }

    /// What one pass found.
    struct Result: Sendable {
        /// Every defect, in tree order.
        let findings: [AccessibilityFinding]

        /// Whether a cap stopped the walk. A partial result that does not say so is a lie.
        let didHitLimit: Bool

        /// Which checks actually ran, so an empty report can say what was looked at.
        let checksRun: Set<AccessibilityCheck>

        /// Which checks were switched on but still did not run, because Scyther's own UI was
        /// covering the app when the pass was made.
        ///
        /// Kept apart from the checks a developer switched off, rather than folded into the gap
        /// between ``checksRun`` and every check, because the two need opposite things said about
        /// them: one is a setting the developer chose, the other is a measurement Scyther refused
        /// to make because it could only have been wrong. Telling a developer they had switched
        /// contrast off when they had not would be its own small lie.
        let checksSkippedWhileCovered: Set<AccessibilityCheck>

        /// Which checks ran but could not measure anything at all.
        ///
        /// The third state, and the one whose absence was the worst thing the report did: a
        /// failed window capture, or a screen on which every candidate element turned out to be
        /// unreadable, produced no findings — and "no findings" was rendered exactly the same way
        /// as "nothing wrong". Seven distinct ways of failing to measure all came out as a clean
        /// bill of health.
        ///
        /// It is deliberately not ``checksSkippedWhileCovered``: that set's banner says the check
        /// was skipped *while Scyther was covering the app*, which is a specific and, for a failed
        /// capture, false reason. A check in this set was run and honestly attempted; there was
        /// simply nothing legible to measure.
        let checksUnmeasurable: Set<AccessibilityCheck>

        /// Creates a result.
        ///
        /// Written out rather than left to the synthesised memberwise initialiser so
        /// ``checksSkippedWhileCovered`` and ``checksUnmeasurable`` can default to empty: nearly
        /// every pass — and every test that predates them — has nothing in either, and a `let`
        /// with an initial value would be left out of the synthesised initialiser altogether.
        ///
        /// - Parameters:
        ///   - findings: Every defect found, in tree order.
        ///   - didHitLimit: Whether a cap stopped the walk.
        ///   - checksRun: Which checks actually ran.
        ///   - checksSkippedWhileCovered: Which enabled checks were skipped because Scyther's own
        ///     UI was covering the app.
        ///   - checksUnmeasurable: Which checks ran but could measure nothing.
        init(findings: [AccessibilityFinding],
             didHitLimit: Bool,
             checksRun: Set<AccessibilityCheck>,
             checksSkippedWhileCovered: Set<AccessibilityCheck> = [],
             checksUnmeasurable: Set<AccessibilityCheck> = []) {
            self.findings = findings
            self.didHitLimit = didHitLimit
            self.checksRun = checksRun
            self.checksSkippedWhileCovered = checksSkippedWhileCovered
            self.checksUnmeasurable = checksUnmeasurable
        }
    }

    /// The traits that mark an element a user is meant to reach with a finger.
    private static let interactiveTraits: UIAccessibilityTraits = [.button, .link, .adjustable]

    /// Apple's minimum comfortable target, in points. Below it, there is something to say.
    private static let minimumTargetSide: CGFloat = 44

    /// Below this, a target is not slightly short — it is a miss.
    ///
    /// 24pt, because it is the only number in this rule anyone can cite: WCAG 2.5.8 Target Size
    /// (Minimum) is the AA success criterion and sets 24 × 24 CSS pixels as the floor. The line
    /// used to be drawn at 32, which appears in no guideline at all — HIG says 44, WCAG 2.5.5
    /// (AAA) says 44, WCAG 2.5.8 (AA) says 24 — and the consequence was a triage list whose
    /// *errors* were dominated by the least actionable findings there are: inline text links and
    /// UIKit's own back button and slider, all of which sit between 24 and 32. Everything from
    /// 24 up to Apple's 44 is a warning: short of the platform's guidance, but not short of any
    /// standard, and not something a developer can be told is broken.
    private static let belowAnyGuidelineSide: CGFloat = 24

    /// The traits that mark an element that draws something worth measuring the contrast of.
    private static let textTraits: UIAccessibilityTraits = [.staticText, .button]

    /// WCAG 1.4.3's ratio for ordinary text.
    private static let textRatio: Double = 4.5

    /// WCAG 1.4.3's ratio for large text, and 1.4.11's for non-text content. The same number for
    /// two different reasons, which is why it is named for neither.
    private static let relaxedRatio: Double = 3.0

    /// The point size at or above which WCAG treats text as large.
    ///
    /// WCAG's "18 point" is a CSS point and iOS points are not CSS points, so this is a
    /// judgement rather than a conversion: 18 iOS points is the size at which iOS text reads as
    /// a heading, it is what Apple's own accessibility guidance uses, and erring by a point in
    /// the strict direction costs a developer a warning they can dismiss while erring the other
    /// way hides a real failure.
    private static let largeTextPointSize: CGFloat = 18

    /// The point size at or above which *bold* text is large, per the same criterion.
    private static let largeBoldTextPointSize: CGFloat = 14

    /// Audits a tree.
    ///
    /// - Parameters:
    ///   - root: The node to walk from.
    ///   - checks: The checks to run. One that is not named here is not run at all.
    ///   - sampler: How pixels are read for the contrast check, or `nil` when contrast is not
    ///     being run — or when it is being run and there are no pixels to read, in which case
    ///     the caller says so through `checksUnmeasurable`.
    ///   - checksSkippedWhileCovered: Checks the caller left out of `checks` because Scyther's own
    ///     UI was covering the app, carried through onto the result so the report can say so.
    ///     Nothing here changes what this method does — the decision belongs to
    ///     ``AccessibilityAudit/auditKeyWindow()``, which is the only caller that can see a real
    ///     screen — so it is purely passed along.
    ///   - checksUnmeasurable: Checks the caller already knows could measure nothing, most often
    ///     because the window snapshot failed. Unioned with anything this pass discovers for
    ///     itself.
    ///   - deadline: When the pass must stop. `nil` starts a fresh ``budget`` from now; a caller
    ///     that has already spent main-thread time on this pass — snapshotting a window, say —
    ///     passes the deadline it started with, so the budget bounds the whole pass rather than
    ///     only the part of it that happens in here.
    /// - Returns: The findings, whether the walk was truncated, which checks ran, and which
    ///   could not answer.
    func audit(root: AuditNode,
               checks: Set<AccessibilityCheck>,
               sampler: ContrastSampling?,
               checksSkippedWhileCovered: Set<AccessibilityCheck> = [],
               checksUnmeasurable: Set<AccessibilityCheck> = [],
               deadline: Date? = nil) -> Result {
        let passDeadline = deadline ?? now().addingTimeInterval(Self.budget)
        let walked = collect(root: root, deadline: passDeadline)
        var findings: [AccessibilityFinding] = []
        var didHitLimit = walked.didHitLimit
        var contrastCandidates = 0
        var contrastMeasurements = 0

        for node in walked.nodes {
            // The same deadline the walk ran under. Every iteration below can crop and rasterise
            // a region of a window bitmap, so this loop is the expensive half of the pass and
            // the half a budget checked only inside the walk never reached.
            guard now() < passDeadline else {
                didHitLimit = true
                break
            }

            if checks.contains(.missingLabel), let finding = missingLabelFinding(for: node) {
                findings.append(finding)
            }
            if checks.contains(.touchTarget), let finding = touchTargetFinding(for: node) {
                findings.append(finding)
            }
            if checks.contains(.contrast), let sampler {
                switch contrastOutcome(for: node, sampler: sampler) {
                case .notApplicable:
                    break
                case .unmeasurable:
                    contrastCandidates += 1
                case .measured(let finding):
                    contrastCandidates += 1
                    contrastMeasurements += 1
                    if let finding { findings.append(finding) }
                }
            }
        }

        // A contrast check that looked at candidates and could read none of them has not passed
        // them; it has failed to measure them, and saying so is the whole point of the third
        // state. A screen with no text at all is a different thing and stays silent.
        var unmeasurable = checksUnmeasurable
        if checks.contains(.contrast), sampler != nil,
           contrastCandidates > 0, contrastMeasurements == 0 {
            unmeasurable.insert(.contrast)
        }

        return Result(findings: findings,
                      didHitLimit: didHitLimit,
                      checksRun: checks,
                      checksSkippedWhileCovered: checksSkippedWhileCovered,
                      checksUnmeasurable: unmeasurable)
    }

    /// The finding for an element VoiceOver could not name, if there is one.
    ///
    /// Stated as an exemption list rather than as a trait list, which is the inverse of how it
    /// began. Gating on "carries one of these traits" meant an element with `.none` traits — a
    /// custom control whose author set `isAccessibilityElement` and forgot everything else, which
    /// is a half-finished job rather than a rare one — was checked by nothing at all and scored
    /// the same as a finished one. Anything VoiceOver will land on and read nothing from is a
    /// defect whatever its traits; the two things that make it not a defect are that the element
    /// reads its own content (`.staticText`) or that it has a value to read instead.
    ///
    /// - Parameter node: The element to check.
    /// - Returns: The finding, or `nil` when the element is named or exempt.
    private func missingLabelFinding(for node: AuditNode) -> AccessibilityFinding? {
        guard node.isAccessibilityElementNode else { return nil }
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed?.isEmpty ?? true else { return nil }
        guard !node.traits.contains(.staticText) else { return nil }

        let value = (node as? AuditNodeDetails)?.auditAccessibilityValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value?.isEmpty ?? true else { return nil }

        return AccessibilityFinding(
            check: .missingLabel,
            severity: .error,
            frame: node.frameInWindow,
            elementName: Self.name(for: node),
            detail: localized("VoiceOver reads this element with no name.")
        )
    }

    /// The finding for a target smaller than a finger, if there is one.
    ///
    /// - Parameter node: The element to check.
    /// - Returns: The finding, or `nil` when the target is big enough or is not a target.
    private func touchTargetFinding(for node: AuditNode) -> AccessibilityFinding? {
        guard !node.traits.intersection(Self.interactiveTraits).isEmpty else { return nil }
        let size = node.frameInWindow.size
        guard size.width < Self.minimumTargetSide || size.height < Self.minimumTargetSide else {
            return nil
        }

        let shortest = min(size.width, size.height)
        // A link is capped at a warning however small it is. WCAG 2.5.8 carries an explicit
        // exception for a target "in a sentence or block of text", and an inline link's frame is
        // its glyph run — around 18pt tall. Nobody makes body-copy links 44pt tall, so calling
        // one an error is an unactionable red box, and unactionable red boxes are what teach a
        // developer to stop reading them. It stays a warning rather than disappearing because a
        // standalone link styled as a button is a real miss and this cannot tell the two apart.
        let isCappedAtWarning = node.traits.contains(.link)
        let severity: AccessibilitySeverity =
            !isCappedAtWarning && shortest < Self.belowAnyGuidelineSide ? .error : .warning

        return AccessibilityFinding(
            check: .touchTarget,
            severity: severity,
            frame: node.frameInWindow,
            elementName: Self.name(for: node),
            detail: localized("\(Self.points(size.width)) × \(Self.points(size.height))pt, under the 44 × 44pt minimum.")
        )
    }

    /// What to call an element in the report.
    ///
    /// An element with no label is named by what it is and where it is, because the finding that
    /// says "this has nothing to call it" cannot then have nothing to call it.
    ///
    /// - Parameter node: The element to name.
    /// - Returns: Its label, or its type and origin.
    private static func name(for node: AuditNode) -> String {
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        let origin = node.frameInWindow.origin
        return localized("\(node.typeName) at \(points(origin.x)), \(points(origin.y))")
    }

    /// A measurement, to one decimal place.
    ///
    /// - Parameter value: The value in points.
    /// - Returns: The formatted number.
    private static func points(_ value: CGFloat) -> String {
        String(format: "%.1f", value) // scyther:unlocalised a number, formatted
    }

    /// What the contrast check made of one element.
    ///
    /// Three cases rather than an optional finding, because "this is not text" and "this is text
    /// and I could not read a single pixel of it" have to be told apart by the caller: the first
    /// is silence, the second is the difference between a clean report and an honest one.
    private enum ContrastOutcome {
        /// Not something this check measures.
        case notApplicable
        /// A candidate, whose pixels could not be turned into a ratio.
        case unmeasurable
        /// A candidate that was measured, and the finding if it failed.
        case measured(AccessibilityFinding?)
    }

    /// Measures one element's contrast.
    ///
    /// - Parameters:
    ///   - node: The element to measure.
    ///   - sampler: Where the pixels come from.
    /// - Returns: What happened, per ``ContrastOutcome``.
    private func contrastOutcome(for node: AuditNode, sampler: ContrastSampling) -> ContrastOutcome {
        guard !node.traits.intersection(Self.textTraits).isEmpty else { return .notApplicable }
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return .notApplicable }

        // WCAG 1.4.3 exempts "text or images of text that are part of an inactive user interface
        // component" outright. A greyed-out button measures 2–3:1 by design and is on screen
        // constantly, so this is not a threshold argument — the success criterion does not apply,
        // and every finding of that class was wrong.
        guard !node.traits.contains(.notEnabled) else { return .notApplicable }

        guard let measured = ContrastAnalyser.measure(pixels: sampler.samples(in: node.frameInWindow)) else {
            return .unmeasurable
        }

        let threshold = Self.contrastThreshold(for: node)
        guard measured.ratio < threshold else { return .measured(nil) }

        return .measured(AccessibilityFinding(
            check: .contrast,
            severity: .warning,
            frame: node.frameInWindow,
            elementName: Self.name(for: node),
            detail: localized("About \(Self.ratio(measured.ratio)):1, under \(Self.ratio(threshold)):1. Estimated from \(measured.foreground.hexDescription) on \(measured.background.hexDescription).")
        ))
    }

    /// The ratio `node` has to clear.
    ///
    /// Three rules, in order of how much is known about the element:
    ///
    /// - **It does not draw text.** WCAG 1.4.11 grades graphical objects and the visual
    ///   boundaries of components at 3:1, not 1.4.3's 4.5:1. An icon-only button satisfies the
    ///   old gate — a `.button` trait and a non-empty label — while containing no text at all,
    ///   so a conformant grey chevron at 3.4:1 was reported as a failure. Having a *name* is
    ///   evidence that an element is not text, not evidence that it is.
    /// - **It draws text at a size that can be read.** Then WCAG's real large-text rule applies:
    ///   18pt, or 14pt bold.
    /// - **It draws text and the size cannot be read** — a synthetic element, a custom view. Then
    ///   the strict threshold, with no relaxation, because the relaxation can only ever hide a
    ///   failure.
    ///
    /// What this replaces was a 24pt *frame height* proxy, which is not a proxy for point size:
    /// it is a proxy for line count plus padding. Every label that wrapped to two lines, and
    /// every button a developer had just padded to 44pt to satisfy this auditor's own touch
    /// target check, was silently regraded from 4.5:1 to 3:1 — the two checks pulling against
    /// each other, in the direction of silence, on ordinary body copy.
    ///
    /// - Parameter node: The element to grade.
    /// - Returns: The minimum acceptable ratio.
    private static func contrastThreshold(for node: AuditNode) -> Double {
        let details = node as? AuditNodeDetails
        let drawsText = node.traits.contains(.staticText) || (details?.auditDrawsText ?? false)
        guard drawsText else { return relaxedRatio }

        guard let pointSize = details?.auditFontPointSize else { return textRatio }
        let isLarge = pointSize >= largeTextPointSize
            || (pointSize >= largeBoldTextPointSize && details?.auditFontIsBold == true)
        return isLarge ? relaxedRatio : textRatio
    }

    /// A ratio, to one decimal place.
    ///
    /// - Parameter value: The ratio.
    /// - Returns: The formatted number.
    private static func ratio(_ value: Double) -> String {
        String(format: "%.1f", value) // scyther:unlocalised a number, formatted
    }
}
