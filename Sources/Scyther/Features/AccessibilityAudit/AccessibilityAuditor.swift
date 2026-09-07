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
/// ``AccessibilityAuditor/contrastThreshold(drawsText:traits:details:)``, which stays at the strict threshold rather
/// than guessing when no size can be read.
@MainActor
protocol AuditNodeDetails {
    /// The point size of the text the node draws, or `nil` when it draws none or cannot say.
    var auditFontPointSize: CGFloat? { get }

    /// Whether that text is bold, which lowers WCAG's large-text threshold.
    var auditFontIsBold: Bool { get }

    /// Whether the node actually draws text, as opposed to having a name for one — or `nil` when
    /// it genuinely cannot say.
    ///
    /// Three-valued on purpose. The contrast threshold is 4.5:1 for text and 3:1 for everything
    /// else, so answering `false` when the truth is "I don't know" hands the lenient grade to every
    /// node that cannot answer — which was every SwiftUI element, every custom view and every
    /// `UITableViewCell` on the screen. `nil` lets ``AccessibilityAuditor/contrastThreshold(drawsText:traits:details:)``
    /// resolve the unknown in the direction that can only ever produce a warning a developer can
    /// dismiss, rather than in the direction that hides a failure.
    var auditDrawsText: Bool? { get }

    /// What VoiceOver would read as the node's value, if anything.
    var auditAccessibilityValue: String? { get }
}

extension AuditNodeDetails {
    /// Nothing known, which is the right answer for any node that has not overridden these.
    var auditFontPointSize: CGFloat? { nil }

    /// Nothing known, so not bold.
    var auditFontIsBold: Bool { false }

    /// Nothing known, and saying so — see ``auditDrawsText`` for why this is not `false`.
    var auditDrawsText: Bool? { nil }

    /// Nothing known, so no value.
    var auditAccessibilityValue: String? { nil }
}

extension UIView: AuditNodeDetails {
    /// The font of the view's own text, for the handful of UIKit views that draw text directly.
    ///
    /// A `UIButton`'s title label rather than the button, because that is where the font lives —
    /// and `titleLabel` is populated whichever of the three authoring paths set the title, so a
    /// `setAttributedTitle(_:for:)` or `UIButton.Configuration` title is read here as well as a
    /// plain one.
    ///
    /// Anything else — a container, a custom view drawing text itself, a SwiftUI backing view —
    /// reports nothing rather than a guess.
    private var auditFont: UIFont? {
        if let label = self as? UILabel { return label.font }
        if let field = self as? UITextField { return field.font }
        if let textView = self as? UITextView { return textView.font }
        if let button = self as? UIButton { return button.titleLabel?.font }
        return nil
    }

    /// The smallest point size found in an attributed string's runs, or `nil` when it has none.
    ///
    /// `UILabel.font` is documented as the fallback typeface and has nothing to do with the fonts
    /// inside `attributedText`: a label whose `font` is 20pt but whose runs are all 11pt was graded
    /// at 3:1 and passed at 3.2:1. The *minimum* run is the right reading rather than the first or
    /// the commonest one, because the strict threshold has to hold for the smallest text present —
    /// grading a paragraph by its heading run is the same silent relaxation in a different place.
    ///
    /// - Parameter text: The attributed string to inspect.
    /// - Returns: The smallest run's point size, or `nil` when no run names a font.
    private static func smallestRunPointSize(in text: NSAttributedString) -> CGFloat? {
        var smallest: CGFloat?
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            guard let font = value as? UIFont else { return }
            smallest = min(smallest ?? font.pointSize, font.pointSize)
        }
        return smallest
    }

    /// The attributed text this view draws, if it draws any.
    private var auditAttributedText: NSAttributedString? {
        if let label = self as? UILabel { return label.attributedText }
        if let field = self as? UITextField { return field.attributedText }
        if let textView = self as? UITextView { return textView.attributedText }
        if let button = self as? UIButton { return button.currentAttributedTitle }
        return nil
    }

    /// The point size the view draws its text at, already scaled by Dynamic Type — which is what
    /// WCAG's rule is about, since the size on screen is the size the reader reads.
    ///
    /// Three readings, each of which `font.pointSize` alone gets wrong, and all three resolved in
    /// the strict direction because a threshold that is one level too strict costs a warning and
    /// one that is too lenient costs a defect:
    ///
    /// - the smallest run of an attributed string, rather than the fallback `font` those runs do
    ///   not use;
    /// - `adjustsFontSizeToFitWidth`, where UIKit shrinks the drawn glyphs as far as
    ///   `minimumScaleFactor` without ever touching `font`, so a 20pt label can be rendering at
    ///   11pt and WCAG's rule is about what is on the screen;
    /// - `nil` rather than a guess for every view that is not one of the four UIKit text views.
    var auditFontPointSize: CGFloat? {
        guard let base = auditAttributedText.flatMap({ Self.smallestRunPointSize(in: $0) }) ?? auditFont?.pointSize else {
            return nil
        }
        guard let label = self as? UILabel, label.adjustsFontSizeToFitWidth else { return base }
        let floorFactor = label.minimumScaleFactor
        guard floorFactor > 0, floorFactor < 1 else { return base }
        return base * floorFactor
    }

    /// Whether the resolved font is bold, read from the descriptor's symbolic traits so a bold
    /// text style counts as well as an explicitly bold face.
    var auditFontIsBold: Bool {
        auditFont?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
    }

    /// Whether the view has text in it right now, or `nil` for a view that cannot know.
    ///
    /// An icon-only `UIButton` has a name and no title, which is exactly the distinction the
    /// contrast threshold turns on: WCAG grades text at 4.5:1 and non-text content at 3:1, and
    /// "has an accessibility label" is evidence of the former only if you confuse a name with
    /// content.
    ///
    /// A button is asked through `titleLabel?.text` rather than `currentTitle`. `currentTitle` is
    /// `nil` when the title was set with `setAttributedTitle(_:for:)` and is not dependable for a
    /// `UIButton.Configuration` title either, so "Forgot password?" as an underlined attributed
    /// title, and every modern `.plain`/`.borderless` configuration button, answered "draws no
    /// text" and dropped a threshold level. `UILabel.text` returns the plain string of whatever the
    /// label is showing, and UIKit populates `titleLabel` in all three authoring paths.
    ///
    /// Anything that is not one of the four UIKit text views answers `nil`, not `false`: a
    /// `UIStackView`, a custom view drawing its own string and a SwiftUI backing view all draw text
    /// routinely and none of them can be asked.
    var auditDrawsText: Bool? {
        if let label = self as? UILabel { return label.text?.isEmpty == false }
        if let field = self as? UITextField { return field.text?.isEmpty == false }
        if let textView = self as? UITextView { return textView.text?.isEmpty == false }
        if let button = self as? UIButton { return button.titleLabel?.text?.isEmpty == false }
        return nil
    }

    /// Direct read of `accessibilityValue`.
    var auditAccessibilityValue: String? { accessibilityValue }
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
    nonisolated static let budget: TimeInterval = 0.25

    /// How long a pass that also captures the window is allowed to take, in seconds.
    ///
    /// A separate number because the two passes do different amounts of work and are read by the
    /// developer in different postures. ``budget`` bounds the pass that runs on every navigation,
    /// where the only acceptable cost is one the developer cannot feel. A pass that runs the
    /// contrast check has to rasterise the whole window first — `drawHierarchy(afterScreenUpdates:
    /// true)`, measured at 436ms on a real screen — and that does not fit inside a quarter of a
    /// second at all. Budgeting it at ``budget`` would not have made it faster; it would have made
    /// every report an empty one with a truncation banner over it, which is the worst of both.
    ///
    /// Two seconds, because the snapshot is the floor and the walk and the per-element sampling sit
    /// on top of it, and because this pass only ever happens when a developer has asked for a
    /// report and is waiting for one. It is still a bound: a screen that cannot be audited in two
    /// seconds gives back what it has and says it stopped early.
    nonisolated static let reportBudget: TimeInterval = 2.0

    /// Reads the current time, so a test can spend the budget deterministically.
    ///
    /// A wall-clock budget tested against the wall clock is a test that either sleeps or flakes.
    /// Taking the clock through a closure lets `AccessibilityAuditorWalkTests` drive it forward by
    /// hand, and costs production nothing: the default is `Date.init` itself.
    var now: () -> Date = Date.init

    /// One element the walk found, with the geometry every rule downstream needs.
    ///
    /// `frameInWindow` is not a property read: for a `UIView` it converts through the superview
    /// chain and, when Scyther's own sheet is up, walks that chain a second time to find the
    /// untransformed measurement space; for a synthetic element it first walks an
    /// `accessibilityContainer` chain to resolve a window. The walk needs it, the visibility test
    /// needs it, and then each of the three checks and the element-naming helper read it again —
    /// up to eight full ancestor climbs per node, and at the 5,000-node cap that is hundreds of
    /// thousands of pointer chases inside a 0.25s budget. Computing it once at the point the node
    /// is admitted and carrying it is the whole of this type.
    struct AuditCandidate {
        /// The element itself.
        let node: AuditNode

        /// Where it is, in the space the audit measures in. Read once, here.
        let frameInWindow: CGRect

        /// What VoiceOver is told this element is. Read once, here.
        ///
        /// Every accessibility property on `NSObject` is a string-keyed lookup into an associated
        /// dictionary, taken behind a dispatch barrier. The two rules and the element-naming helper
        /// between them read this three times and ``accessibilityLabelText`` three times for a
        /// single candidate, for values that cannot change inside one pass. Reading them where the
        /// candidate is built costs the same as the first read did and makes the other four free.
        let traits: UIAccessibilityTraits

        /// The label VoiceOver would read, already trimmed of whitespace, or `nil` when there is
        /// none to read.
        ///
        /// Trimmed here rather than at each of the three places that used to ask, because every one
        /// of them wanted the same question answered — "is there a name" — and answered it with its
        /// own `trimmingCharacters(in:)` over the same string.
        let label: String?

        /// Creates a candidate, reading everything the rules will need from the node exactly once.
        ///
        /// - Parameters:
        ///   - node: The element the walk found.
        ///   - frameInWindow: Its already-resolved frame.
        @MainActor
        init(node: AuditNode, frameInWindow: CGRect) {
            self.node = node
            self.frameInWindow = frameInWindow
            self.traits = node.traits
            let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
    }

    /// Every element worth checking, in tree order.
    ///
    /// Kept as a thin projection of ``collectCandidates(root:deadline:)`` because a caller that
    /// only wants to know *which* nodes were found — every test of the walk's caps, ordering and
    /// skip rules — should not have to know about the geometry the pass caches for the rules.
    ///
    /// - Parameters:
    ///   - root: The node to walk from, usually the key window.
    ///   - deadline: When the walk must stop, shared with the rest of the pass. `nil` starts a
    ///     fresh ``budget`` from now, which is what a caller walking a tree on its own wants.
    /// - Returns: The elements found, and whether a cap stopped the walk before it finished.
    func collect(root: AuditNode, deadline: Date? = nil) -> (nodes: [AuditNode], didHitLimit: Bool) {
        let walked = collectCandidates(root: root, deadline: deadline)
        return (walked.candidates.map(\.node), walked.didHitLimit)
    }

    /// Every element worth checking, in tree order, each with its frame already resolved.
    ///
    /// - Parameters:
    ///   - root: The node to walk from, usually the key window.
    ///   - deadline: When the walk must stop, shared with the rest of the pass. `nil` starts a
    ///     fresh ``budget`` from now.
    /// - Returns: The candidates found, and whether a cap stopped the walk before it finished.
    func collectCandidates(root: AuditNode,
                           deadline: Date? = nil) -> (candidates: [AuditCandidate], didHitLimit: Bool) {
        var found: [AuditCandidate] = []
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
        ///
        /// **Every limit stops the whole walk, not the branch it fired on.** `didHitLimit` is set
        /// and the first line of this function then unwinds the recursion, so nothing after the
        /// stopping point *in tree order* is walked at all — not the rest of the branch, and not the
        /// toolbar, tab bar or floating button that came after it. That is deliberate for the
        /// deadline and for the node cap, which exist to bound how long the main thread is held and
        /// how much work one pass may do, and neither is bounded by truncating one branch and
        /// carrying on. But it composes sharply with counting skipped nodes: a long list's
        /// scrolled-away cells consume the budget, so the cap can fire *inside* the table and the
        /// bottom half of an ordinary screen is never reached. The report is not allowed to describe
        /// that as "there was too much to check" — see
        /// ``AccessibilityAuditViewModel/truncationDescription``, which says instead that the walk
        /// stopped at a limit and never reached the rest of the screen, and that what is missing is
        /// unchecked rather than clean. All three limits raise the same flag because that one
        /// sentence is true of all three; the report does not need to learn which fired.
        func walk(_ node: AuditNode, depth: Int, clearedAncestor: AnyObject?) {
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

            // The ownership climb stops at the parent, which this walk cleared on the way down —
            // see ``AuditNode/isScytherOwned(below:)``. The frame and the visibility answer come
            // from one question, resolved once here and carried on the candidate rather than being
            // read again by every rule that follows.
            guard !node.isScytherOwned(below: clearedAncestor) else { return }
            guard let frame = node.frameInWindowIfVisible else { return }

            if node.isAccessibilityElementNode {
                found.append(AuditCandidate(node: node, frameInWindow: frame))
                return
            }

            let cleared = node.ownershipIdentity ?? clearedAncestor
            for child in node.children {
                walk(child, depth: depth + 1, clearedAncestor: cleared)
            }
        }

        walk(root, depth: 0, clearedAncestor: nil)
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

        /// How many elements the contrast check was asked about.
        ///
        /// Published because the *caller* has to decide what the report may claim from a pass that
        /// read some of the screen and not the rest, and it cannot re-derive this honestly. It was
        /// re-derived, once: a wrapper around the sampler counted crops and asked
        /// ``ContrastAnalyser/measure(pixels:)`` again on a strided subsample of each one. Three
        /// things were wrong with that. It counted *regions*, not elements — one row with four
        /// labels in it counted four times, so the fraction meant something different on a list
        /// screen than on a form. Its stride walked a row-major grid 64 wide in steps that are
        /// often factors of 64, so the probe read the same handful of columns of every row and
        /// could miss a glyph stem entirely, calling a crop unreadable that measured fine. And it
        /// answered a different question from the real one wherever the two rules underneath
        /// disagreed — ``ContrastAnalyser/smallestUsefulSample`` refuses a crop of fewer than
        /// sixteen pixels, which a subsample can fall under while the crop itself would not.
        ///
        /// The auditor already has the exact answer, per element, from the same call the findings
        /// come from. Handing it over costs an `Int` and cannot drift.
        let contrastCandidates: Int

        /// How many of ``contrastCandidates`` yielded a measurement.
        let contrastMeasurements: Int

        /// Creates a result.
        ///
        /// Written out rather than left to the synthesised memberwise initialiser so
        /// ``checksSkippedWhileCovered``, ``checksUnmeasurable`` and the two contrast counts can
        /// default: nearly every pass — and every test that predates them — has nothing in any of
        /// them, and a `let` with an initial value would be left out of the synthesised
        /// initialiser altogether.
        ///
        /// - Parameters:
        ///   - findings: Every defect found, in tree order.
        ///   - didHitLimit: Whether a cap stopped the walk.
        ///   - checksRun: Which checks actually ran.
        ///   - checksSkippedWhileCovered: Which enabled checks were skipped because Scyther's own
        ///     UI was covering the app.
        ///   - checksUnmeasurable: Which checks ran but could measure nothing.
        ///   - contrastCandidates: How many elements contrast was asked about.
        ///   - contrastMeasurements: How many of those it could read.
        init(findings: [AccessibilityFinding],
             didHitLimit: Bool,
             checksRun: Set<AccessibilityCheck>,
             checksSkippedWhileCovered: Set<AccessibilityCheck> = [],
             checksUnmeasurable: Set<AccessibilityCheck> = [],
             contrastCandidates: Int = 0,
             contrastMeasurements: Int = 0) {
            self.findings = findings
            self.didHitLimit = didHitLimit
            self.checksRun = checksRun
            self.checksSkippedWhileCovered = checksSkippedWhileCovered
            self.checksUnmeasurable = checksUnmeasurable
            self.contrastCandidates = contrastCandidates
            self.contrastMeasurements = contrastMeasurements
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
        let walked = collectCandidates(root: root, deadline: passDeadline)
        var findings: [AccessibilityFinding] = []
        var didHitLimit = walked.didHitLimit
        var contrastCandidates = 0
        var contrastMeasurements = 0

        for candidate in walked.candidates {
            // The same deadline the walk ran under. Every iteration below can crop and rasterise
            // a region of a window bitmap, so this loop is the expensive half of the pass and
            // the half a budget checked only inside the walk never reached.
            guard now() < passDeadline else {
                didHitLimit = true
                break
            }

            if checks.contains(.missingLabel), let finding = missingLabelFinding(for: candidate) {
                findings.append(finding)
            }
            if checks.contains(.touchTarget), let finding = touchTargetFinding(for: candidate) {
                findings.append(finding)
            }
            if checks.contains(.contrast), let sampler {
                // Each sample crops a `CGImage`, allocates a `CGContext` and fills a buffer of up
                // to 64 × 64 RGBA pixels — a quarter of a megabyte of autoreleased Core Graphics
                // objects per candidate, and at the node cap nothing drained until the whole pass
                // returned. Draining per element keeps the pass's peak flat instead of linear in
                // the number of text elements on screen, which matters most on exactly the
                // memory-heavy screens somebody runs an audit over.
                let outcome = autoreleasepool { contrastOutcome(for: candidate, sampler: sampler) }
                switch outcome {
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
                      checksUnmeasurable: unmeasurable,
                      contrastCandidates: contrastCandidates,
                      contrastMeasurements: contrastMeasurements)
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
    /// - Parameter candidate: The element to check, with its frame already resolved.
    /// - Returns: The finding, or `nil` when the element is named or exempt.
    private func missingLabelFinding(for candidate: AuditCandidate) -> AccessibilityFinding? {
        // No `isAccessibilityElementNode` guard: a candidate exists only because the walk already
        // asked that question and got `true`, and asking it again was a second string-keyed
        // accessibility read per element for an answer that cannot have changed.
        guard candidate.label == nil else { return nil }
        guard !candidate.traits.contains(.staticText) else { return nil }

        let value = (candidate.node as? AuditNodeDetails)?.auditAccessibilityValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value?.isEmpty ?? true else { return nil }

        return AccessibilityFinding(
            check: .missingLabel,
            severity: .error,
            frame: candidate.frameInWindow,
            elementName: Self.name(for: candidate),
            detail: localized("VoiceOver reads this element with no name.")
        )
    }

    /// The finding for a target smaller than a finger, if there is one.
    ///
    /// The two severities carry two different sentences, because they cite two different numbers
    /// and the developer cannot act on a number they are not shown. One string reading "under the
    /// 44 × 44pt minimum" for both meant the 24pt line — the entire point of the severity split,
    /// and the only figure in this rule anyone can cite a standard for — appeared nowhere a
    /// developer could see it: a 20pt element and a 43pt element differed only by the colour of a
    /// dot.
    ///
    /// - Parameter candidate: The element to check, with its frame already resolved.
    /// - Returns: The finding, or `nil` when the target is big enough or is not a target.
    private func touchTargetFinding(for candidate: AuditCandidate) -> AccessibilityFinding? {
        guard !candidate.traits.intersection(Self.interactiveTraits).isEmpty else { return nil }
        let size = candidate.frameInWindow.size
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
        let isCappedAtWarning = candidate.traits.contains(.link)
        let isError = !isCappedAtWarning && shortest < Self.belowAnyGuidelineSide
        let width = Self.points(size.width)
        let height = Self.points(size.height)

        return AccessibilityFinding(
            check: .touchTarget,
            severity: isError ? .error : .warning,
            frame: candidate.frameInWindow,
            elementName: Self.name(for: candidate),
            detail: isError
                ? localized("\(width) × \(height)pt, under WCAG 2.5.8's 24 × 24pt minimum.")
                : localized("\(width) × \(height)pt, under Apple's 44 × 44pt guidance.")
        )
    }

    /// What to call an element in the report.
    ///
    /// An element with no label is named by what it is and where it is, because the finding that
    /// says "this has nothing to call it" cannot then have nothing to call it.
    ///
    /// - Parameter candidate: The element to name, with its label and frame already resolved — so
    ///   naming an element costs neither another accessibility read nor another climb up its
    ///   ancestor chain.
    /// - Returns: Its label, or its type and origin.
    private static func name(for candidate: AuditCandidate) -> String {
        if let label = candidate.label { return label }
        let frame = candidate.frameInWindow
        return localized("\(candidate.node.typeName) at \(points(frame.origin.x)), \(points(frame.origin.y))")
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

    /// One rectangle of an element worth sampling, and the standard the text in it is held to.
    private struct TextRegion {
        /// Where to sample, in window coordinates.
        let frame: CGRect

        /// The minimum acceptable ratio for whatever is drawn there.
        let threshold: Double

        /// Whether the point size behind that threshold was actually readable, so a finding can
        /// say when the large-text allowance was withheld for want of a size rather than applied
        /// and failed.
        let pointSizeWasKnown: Bool
    }

    /// How deep the sampling descent goes inside one combined element.
    ///
    /// The descent is not the accessibility walk — it deliberately goes *past* the leaf VoiceOver
    /// stops at — so it needs its own bound. A cell's own view hierarchy is a handful of levels;
    /// twelve covers a stack view inside a container inside a content view without ever
    /// approaching the cost of a second full tree walk.
    private static let maximumTextRegionDepth = 12

    /// How many text regions one element is sampled at.
    ///
    /// A row with an icon, a title, a subtitle and a trailing value is four. The cap exists for
    /// the pathological case — a custom "cell" that is really a whole screen — where sampling
    /// every label would spend the pass's entire budget on one element.
    private static let maximumTextRegions = 8

    /// The views inside `view` that actually draw text, including `view` itself.
    ///
    /// The reason this exists is the single most damaging thing round two found. Contrast used to
    /// be gated on the element carrying `.staticText` or `.button`; a `UITableViewCell` or
    /// `UICollectionViewCell` with `isAccessibilityElement = true` carries neither, nor does a
    /// SwiftUI row using `.accessibilityElement(children: .combine)`, nor does a `UITextField`. The
    /// walk stops at the combined element, so the `UILabel`s inside it were never visited either,
    /// and on the most ordinary screen in iOS — a list — *no text was contrast-checked at all* and
    /// the report printed a green tick. Every other gap in this tool produces a missing finding;
    /// that one produced a certificate.
    ///
    /// Descending fixes more than the gate. The combined element's rectangle is mostly background,
    /// so measuring it asks the analyser to find a glyph in a crop that is 95% fill, next to an
    /// avatar and a chevron; each label's own bounds is nearly all text and background and nothing
    /// else. And a `UILabel` can answer ``UIView/auditFontPointSize``, so descending also recovers
    /// the real threshold for text the combined element could never have supplied a size for.
    ///
    /// This is for *sampling only*: nothing found here becomes a finding of its own, is counted as
    /// an element, or appears in the report as a separate row. The element the developer sees is
    /// still the one VoiceOver lands on.
    ///
    /// Hidden and transparent subviews are skipped for the same reason the walk skips them — they
    /// are not on screen — and a text view is not descended into, since a `UILabel`'s internals
    /// are UIKit's business.
    ///
    /// - Parameter view: The view the accessibility walk stopped at.
    /// - Returns: The text-drawing views inside it, outermost first, at most
    ///   ``maximumTextRegions`` of them.
    static func drawnTextViews(in view: UIView) -> [UIView] {
        var found: [UIView] = []

        func descend(_ current: UIView, depth: Int) {
            guard found.count < maximumTextRegions, depth <= maximumTextRegionDepth else { return }
            guard !current.isHidden, current.alpha > 0.01 else { return }
            if current.auditDrawsText == true {
                found.append(current)
                return
            }
            for subview in current.subviews {
                descend(subview, depth: depth + 1)
            }
        }

        descend(view, depth: 0)
        return found
    }

    /// Where to sample one element, and what standard each of those places is held to.
    ///
    /// - Parameter candidate: The element, with its frame already resolved.
    /// - Returns: One region per piece of text actually drawn inside a real view, or the element's
    ///   own rectangle when nothing can be descended into — a synthetic SwiftUI element, or a view
    ///   that draws its own string with no `UILabel` in it.
    private static func textRegions(for candidate: AuditCandidate) -> [TextRegion] {
        if let view = candidate.node as? UIView {
            let drawn = drawnTextViews(in: view)
            if !drawn.isEmpty {
                return drawn.map { text in
                    TextRegion(frame: text.frameInWindow,
                               threshold: contrastThreshold(drawsText: true,
                                                            traits: text.accessibilityTraits,
                                                            details: text),
                               pointSizeWasKnown: text.auditFontPointSize != nil)
                }
            }
        }
        let details = candidate.node as? AuditNodeDetails
        return [TextRegion(frame: candidate.frameInWindow,
                           threshold: contrastThreshold(drawsText: details?.auditDrawsText,
                                                        traits: candidate.traits,
                                                        details: details),
                           pointSizeWasKnown: details?.auditFontPointSize != nil)]
    }

    /// Measures one element's contrast.
    ///
    /// Every region the element draws text in is measured, and the worst of them — the one
    /// furthest below its own threshold — becomes the finding, reported at that region's frame so
    /// the overlay boxes the text that failed rather than the whole row. One element still
    /// produces at most one finding.
    ///
    /// - Parameters:
    ///   - candidate: The element to measure, with its frame already resolved.
    ///   - sampler: Where the pixels come from.
    /// - Returns: What happened, per ``ContrastOutcome``.
    private func contrastOutcome(for candidate: AuditCandidate,
                                 sampler: ContrastSampling) -> ContrastOutcome {
        let node = candidate.node
        let traits = candidate.traits
        // WCAG 1.4.3 exempts "text or images of text that are part of an inactive user interface
        // component" outright. A greyed-out button measures 2–3:1 by design and is on screen
        // constantly, so this is not a threshold argument — the success criterion does not apply,
        // and every finding of that class was wrong.
        guard !traits.contains(.notEnabled) else { return .notApplicable }

        let details = node as? AuditNodeDetails
        guard candidate.label != nil || details?.auditDrawsText == true else { return .notApplicable }

        // An element whose only trait is `.image` is a picture. WCAG grades those under 1.4.11,
        // which this tool does not implement and says so in its documentation; measuring one under
        // 1.4.3 would report a photograph as failing body-text contrast.
        if traits.contains(.image), traits.subtracting([.image, .selected]).isEmpty,
           details?.auditDrawsText != true {
            return .notApplicable
        }

        var worst: (finding: AccessibilityFinding, shortfall: Double)?
        var didMeasureAnything = false

        for region in Self.textRegions(for: candidate) {
            guard let measured = ContrastAnalyser.measure(pixels: sampler.samples(in: region.frame)) else {
                continue
            }
            didMeasureAnything = true
            guard measured.ratio < region.threshold else { continue }

            let shortfall = measured.ratio / region.threshold
            guard shortfall < (worst?.shortfall ?? .greatestFiniteMagnitude) else { continue }

            var detail = localized("About \(Self.ratio(measured.ratio)):1, under \(Self.ratio(region.threshold)):1. Estimated from \(measured.foreground.hexDescription) on \(measured.background.hexDescription).")
            if !region.pointSizeWasKnown, region.threshold == Self.textRatio {
                detail += " " + localized("Point size unknown, so the large-text allowance was not applied.")
            }
            worst = (AccessibilityFinding(check: .contrast,
                                          severity: .warning,
                                          frame: region.frame,
                                          elementName: Self.name(for: candidate),
                                          detail: detail),
                     shortfall)
        }

        // Nothing legible anywhere in the element. That is "could not measure", never a pass —
        // an occluded element, a gradient, a photograph and a crop the sampler never painted all
        // land here, and every one of them used to come back as a confident number or as silence.
        guard didMeasureAnything else { return .unmeasurable }
        return .measured(worst?.finding)
    }

    /// The ratio a piece of content has to clear.
    ///
    /// Three rules, in order of how much is known:
    ///
    /// - **It can say it draws no text, or it is a graphic.** WCAG 1.4.11 grades graphical objects
    ///   and the visual boundaries of components at 3:1, not 1.4.3's 4.5:1. An icon-only `UIButton`
    ///   satisfies the old gate — a `.button` trait and a non-empty label — while containing no
    ///   text at all, so a conformant grey chevron at 3.4:1 was reported as a failure. Having a
    ///   *name* is evidence that an element is not text, not evidence that it is.
    /// - **It draws text at a size that can be read.** Then WCAG's real large-text rule applies:
    ///   18pt, or 14pt bold.
    /// - **Anything else.** The strict threshold, with no relaxation.
    ///
    /// That last rule is the one that changed, and it changed because the previous version
    /// resolved the same unknown two opposite ways one line apart. An unknown *point size* fell
    /// back to strict, correctly reasoned as "the relaxation can only ever hide a failure"; an
    /// unknown *text-ness* fell back to lenient — and since `AccessibilityElementNode` conforms to
    /// nothing, "unknown" was every element SwiftUI has ever produced. A SwiftUI `Button("Continue")`
    /// carries `.button` and not `.staticText`, so its 13pt title was graded at 3:1 and passed at
    /// 3.4:1; so was every `UITableViewCell` that makes itself one VoiceOver stop. Only a node that
    /// can *affirmatively* answer "I draw no text" now earns 3:1, which keeps the icon-only
    /// `UIButton` fixed because a `UIButton` can answer, and `.image` keeps the SwiftUI icon-only
    /// button lenient because that is the one trait SwiftUI does supply for it.
    ///
    /// What all of this replaces was a 24pt *frame height* proxy, which is not a proxy for point
    /// size: it is a proxy for line count plus padding. Every label that wrapped to two lines, and
    /// every button a developer had just padded to 44pt to satisfy this auditor's own touch target
    /// check, was silently regraded from 4.5:1 to 3:1.
    ///
    /// - Parameters:
    ///   - drawsText: Whether text is drawn, or `nil` when that cannot be established.
    ///   - traits: The element's accessibility traits.
    ///   - details: What can be read about the font, if anything.
    /// - Returns: The minimum acceptable ratio.
    private static func contrastThreshold(drawsText: Bool?,
                                          traits: UIAccessibilityTraits,
                                          details: AuditNodeDetails?) -> Double {
        if drawsText == false { return relaxedRatio }
        if drawsText == nil, !traits.contains(.staticText), traits.contains(.image) {
            return relaxedRatio
        }

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
