import UIKit

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

    /// How long the walk is allowed to take before it gives up, in seconds.
    ///
    /// A cap measured in nodes only protects the developer from a walk that is *long*. It does
    /// nothing about a walk that is slow per node, which is the shape a real hierarchy takes when
    /// something below ``AuditNode/children`` turns out to cost more than a property read — and
    /// the walk runs on the main thread, inside the report screen's first appear, so a walk that
    /// takes seconds is a frozen app rather than a slow screen. A quarter of a second is about
    /// the longest the main thread can be held without a developer noticing, and a partial report
    /// that admits it is partial beats a complete one nobody waits for.
    static let budget: TimeInterval = 0.25

    /// Reads the current time, so a test can spend the budget deterministically.
    ///
    /// A wall-clock budget tested against the wall clock is a test that either sleeps or flakes.
    /// Taking the clock through a closure lets `AccessibilityAuditorWalkTests` drive it forward by
    /// hand, and costs production nothing: the default is `Date.init` itself.
    var now: () -> Date = Date.init

    /// Every element worth checking, in tree order.
    ///
    /// - Parameter root: The node to walk from, usually the key window.
    /// - Returns: The elements found, and whether a cap stopped the walk before it finished.
    func collect(root: AuditNode) -> (nodes: [AuditNode], didHitLimit: Bool) {
        var found: [AuditNode] = []
        var didHitLimit = false
        var visited = 0
        let deadline = now().addingTimeInterval(Self.budget)

        /// Walks the tree depth-first, counting every node visited to prevent pathological
        /// hierarchies of containers from bypassing the node cap, and enforcing the depth, node
        /// and time limits.
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
            guard !node.isScytherOwned, node.isVisible, !node.frameInWindow.isEmpty else { return }

            if depth > 0 {
                visited += 1
                guard visited <= Self.maximumNodes else {
                    didHitLimit = true
                    return
                }
            }

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

        /// Creates a result.
        ///
        /// Written out rather than left to the synthesised memberwise initialiser so
        /// ``checksSkippedWhileCovered`` can default to empty: nearly every pass — and every test
        /// that predates it — has nothing skipped for that reason, and a `let` with an initial
        /// value would be left out of the synthesised initialiser altogether.
        ///
        /// - Parameters:
        ///   - findings: Every defect found, in tree order.
        ///   - didHitLimit: Whether a cap stopped the walk.
        ///   - checksRun: Which checks actually ran.
        ///   - checksSkippedWhileCovered: Which enabled checks were skipped because Scyther's own
        ///     UI was covering the app.
        init(findings: [AccessibilityFinding],
             didHitLimit: Bool,
             checksRun: Set<AccessibilityCheck>,
             checksSkippedWhileCovered: Set<AccessibilityCheck> = []) {
            self.findings = findings
            self.didHitLimit = didHitLimit
            self.checksRun = checksRun
            self.checksSkippedWhileCovered = checksSkippedWhileCovered
        }
    }

    /// The traits that mark an element a user is meant to name and reach.
    private static let interactiveTraits: UIAccessibilityTraits = [.button, .link, .adjustable]

    /// The traits that mark an element a user is meant to be able to name.
    private static let nameableTraits: UIAccessibilityTraits =
        [.button, .link, .image, .searchField, .adjustable, .keyboardKey]

    /// Apple's minimum comfortable target, in points.
    private static let minimumTargetSide: CGFloat = 44

    /// Below this, a target is not slightly short — it is a miss.
    private static let seriouslySmallSide: CGFloat = 32

    /// The traits that mark an element that draws text worth measuring.
    private static let textTraits: UIAccessibilityTraits = [.staticText, .button]

    /// The height at which text is treated as large, and held to the lower threshold.
    ///
    /// WCAG's "large" is a point size, which cannot be read off an accessibility element. The
    /// element's height is the closest an outside observer gets, and it is stated as an estimate
    /// rather than dressed up as the real rule.
    private static let largeTextHeight: CGFloat = 24

    /// Audits a tree.
    ///
    /// - Parameters:
    ///   - root: The node to walk from.
    ///   - checks: The checks to run. One that is not named here is not run at all.
    ///   - sampler: How pixels are read for the contrast check, or `nil` when contrast is not
    ///     being run.
    ///   - checksSkippedWhileCovered: Checks the caller left out of `checks` because Scyther's own
    ///     UI was covering the app, carried through onto the result so the report can say so.
    ///     Nothing here changes what this method does — the decision belongs to
    ///     ``AccessibilityAudit/auditKeyWindow()``, which is the only caller that can see a real
    ///     screen — so it is purely passed along.
    /// - Returns: The findings, whether the walk was truncated, and which checks ran.
    func audit(root: AuditNode,
               checks: Set<AccessibilityCheck>,
               sampler: ContrastSampling?,
               checksSkippedWhileCovered: Set<AccessibilityCheck> = []) -> Result {
        let walked = collect(root: root)
        var findings: [AccessibilityFinding] = []

        for node in walked.nodes {
            if checks.contains(.missingLabel), let finding = missingLabelFinding(for: node) {
                findings.append(finding)
            }
            if checks.contains(.touchTarget), let finding = touchTargetFinding(for: node) {
                findings.append(finding)
            }
            if checks.contains(.contrast), let sampler,
               let finding = contrastFinding(for: node, sampler: sampler) {
                findings.append(finding)
            }
        }

        return Result(findings: findings,
                      didHitLimit: walked.didHitLimit,
                      checksRun: checks,
                      checksSkippedWhileCovered: checksSkippedWhileCovered)
    }

    /// The finding for an element VoiceOver could not name, if there is one.
    ///
    /// - Parameter node: The element to check.
    /// - Returns: The finding, or `nil` when the element is named or exempt.
    private func missingLabelFinding(for node: AuditNode) -> AccessibilityFinding? {
        guard !node.traits.intersection(Self.nameableTraits).isEmpty else { return nil }
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed?.isEmpty ?? true else { return nil }

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
        return AccessibilityFinding(
            check: .touchTarget,
            severity: shortest < Self.seriouslySmallSide ? .error : .warning,
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

    /// The finding for text too close in colour to what is behind it, if there is one.
    ///
    /// - Parameters:
    ///   - node: The element to measure.
    ///   - sampler: Where the pixels come from.
    /// - Returns: The finding, or `nil` when the element is not text, cannot be read, or passes.
    private func contrastFinding(for node: AuditNode, sampler: ContrastSampling) -> AccessibilityFinding? {
        guard !node.traits.intersection(Self.textTraits).isEmpty else { return nil }
        let trimmed = node.accessibilityLabelText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }

        guard let measured = ContrastAnalyser.measure(pixels: sampler.samples(in: node.frameInWindow)) else {
            return nil
        }

        let threshold = node.frameInWindow.height >= Self.largeTextHeight ? 3.0 : 4.5
        guard measured.ratio < threshold else { return nil }

        return AccessibilityFinding(
            check: .contrast,
            severity: .warning,
            frame: node.frameInWindow,
            elementName: Self.name(for: node),
            detail: localized("About \(Self.ratio(measured.ratio)):1, under \(Self.ratio(threshold)):1. Estimated from \(measured.foreground.hexDescription) on \(measured.background.hexDescription).")
        )
    }

    /// A ratio, to one decimal place.
    ///
    /// - Parameter value: The ratio.
    /// - Returns: The formatted number.
    private static func ratio(_ value: Double) -> String {
        String(format: "%.1f", value) // scyther:unlocalised a number, formatted
    }
}
