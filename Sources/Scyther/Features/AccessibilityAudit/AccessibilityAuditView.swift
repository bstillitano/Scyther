//
//  AccessibilityAuditView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

#if !os(macOS)
import SwiftUI

/// The screen where a developer reads what the accessibility audit found.
///
/// This is the only screen the audit has — there is no separate settings screen. The toggles
/// that control it (``AccessibilityAudit/liveEnabled`` and each ``AccessibilityCheck``) sit in a
/// settings section at the top, above the report itself, the same way `TouchVisualiserView`
/// carries its own settings rather than sending a developer to a second screen for them.
///
/// The report below the toggles is frozen the moment it loads — see
/// ``AccessibilityAuditViewModel/load()`` — and only changes when **Re-run** is tapped, so
/// findings do not shift under a developer mid-read. The pass itself runs a turn *after* this
/// screen appears rather than inside its first appear, so the navigation push finishes and this
/// list is on screen with a spinner while the walk happens; a walk that held the main thread
/// through the push made the app look frozen rather than busy.
///
/// Tapping a finding's row flashes its box on the live overlay behind this screen, via
/// ``AccessibilityAuditViewModel/onFlash``, wired here to
/// `InterfaceToolkit.instance.accessibilityAuditView.flash(_:)`.
///
/// ## Topics
/// ### Related Types
/// - ``AccessibilityAuditViewModel``
struct AccessibilityAuditView: View {
    /// The view model, constructed with the one closure it needs to audit the real app — see
    /// ``AccessibilityAuditViewModel`` for why the audit itself is injected rather than called
    /// directly.
    @StateObject private var viewModel = AccessibilityAuditViewModel(
        seed: { InterfaceToolkit.instance.accessibilityResultForReport() },
        run: { AccessibilityAudit.instance.auditKeyWindow() }
    )

    var body: some View {
        List {
            settingsSection

            if viewModel.isRunning {
                runningSection
            }

            if viewModel.didHitLimit {
                truncatedBanner
            }

            if !viewModel.checksSkippedWhileCovered.isEmpty {
                coveredBanner
            }

            if !viewModel.checksUnmeasurable.isEmpty {
                unmeasurableBanner
            }

            if !viewModel.checksAwaitingRerun.isEmpty {
                awaitingRerunBanner
            }

            if viewModel.visibleGroups.isEmpty {
                // Only once there is an answer: an empty report during a pass would say "No
                // Issues Found" about a screen nothing has looked at yet.
                if !viewModel.isRunning {
                    emptyState
                }
            } else {
                ForEach(viewModel.visibleGroups) { group in
                    findingsSection(for: group)
                }
            }
        }
        .navigationTitle(localized("Accessibility Audit"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.rerun() }
                } label: {
                    Label(localized("Re-run"), systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRunning)
            }
        }
        .onFirstAppear {
            viewModel.onFlash = { finding in
                InterfaceToolkit.instance.accessibilityAuditView.flash(finding)
            }
            await viewModel.onFirstAppear()
        }
    }

    // MARK: - Settings

    /// Live mode and the three per-check toggles, in one section at the top of the screen — see
    /// the type-level documentation for why there is no separate settings screen for these.
    private var settingsSection: some View {
        Section {
            Toggle(localized("Show Issues On Screen"), isOn: $viewModel.liveEnabled)
            ForEach(AccessibilityCheck.allCases) { check in
                Toggle(check.title, isOn: viewModel.checkBinding(for: check))
            }
        } footer: {
            Text(localized("Draws a box around every finding, live over the running app."))
        }
    }

    // MARK: - Running

    /// Shown while a pass is in flight.
    ///
    /// The pass happens a turn after the screen appears — see
    /// `AccessibilityAuditViewModel.performPass()` — so there is a moment where the report
    /// exists but its answer does not, and a spinner is what says so. Stock `ProgressView`, like
    /// every other indeterminate wait in Scyther.
    private var runningSection: some View {
        Section {
            ProgressView {
                Text(localized("Checking every element on screen…"))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Truncated Walk

    /// Shown when ``AccessibilityAuditViewModel/didHitLimit`` is true: the walk that produced
    /// this report stopped before it finished, so the report is not necessarily the whole
    /// picture. Presenting a truncated result with no warning would tell a developer their
    /// screen is clean when the audit simply never reached the rest of it.
    private var truncatedBanner: some View {
        Section {
            Label(
                localized("This audit stopped early because there was too much to check. This report may be incomplete."),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Covered Screen

    /// Shown when a check was switched on but could not be run because this very screen — or
    /// Scyther's menu — was covering the app.
    ///
    /// A banner rather than a line in the empty state, because it has to be visible whether or
    /// not anything else was found: a report full of missing-label findings that quietly never
    /// measured contrast reads exactly like a screen whose contrast is fine.
    ///
    /// It names the way to get the measurement rather than only refusing to make it. Live mode
    /// draws over the app with nothing of Scyther's presented in front of it, which is the one
    /// state where the pixels behind an element really are the app's own.
    private var coveredBanner: some View {
        Section {
            Label(coveredDescription, systemImage: "eye.slash")
                .foregroundStyle(.orange)
        }
    }

    /// The covered banner's wording: which checks were skipped, and what to switch on to have
    /// them measured against the real screen.
    ///
    /// The live-mode toggle is named through ``localized(_:comment:)`` rather than spelled out in
    /// the sentence, so a developer reading Scyther in French is pointed at the French toggle
    /// sitting a few rows above rather than at an English one that is not there.
    private var coveredDescription: String {
        let names = ListFormatter.localizedString(byJoining: viewModel.checksSkippedWhileCovered.map(\.title))
        let liveToggle = localized("Show Issues On Screen")
        return localized("\(names) not measured while Scyther is covering the app: the colors behind this screen are Scyther's, not your app's. Switch on \(liveToggle) to measure the real screen instead.")
    }

    // MARK: - Unmeasurable Screen

    /// Shown when a check was switched on, was not skipped, and still measured nothing because the
    /// screen could not be captured.
    ///
    /// Deliberately worded away from ``coveredBanner``, which it would otherwise be mistaken for.
    /// That one describes a measurement Scyther declined to make and tells the developer how to get
    /// it; this one describes a measurement iOS refused to supply the pixels for — a window the
    /// system has never presented, or content it will not let anything capture — and there is
    /// nothing to switch. What both must never do is read as an answer about the screen: an
    /// unmeasured screen presented as a measured one is the failure this whole section exists for.
    private var unmeasurableBanner: some View {
        Section {
            Label(unmeasurableDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    /// The unmeasurable banner's wording: which checks ran without being able to measure anything,
    /// and that this says nothing about whether the screen is fine.
    private var unmeasurableDescription: String {
        let names = ListFormatter.localizedString(byJoining: viewModel.checksUnmeasurable.map(\.title))
        return localized("\(names) could not be measured: this screen could not be captured, so there were no pixels to read. This is not a result about your app.")
    }

    // MARK: - Settings Changed Since The Pass

    /// Shown when a check has been switched on since this report was run.
    ///
    /// The report is frozen and the toggles are not, so the two can disagree on the same screen.
    /// A check switched off since the pass simply has its findings hidden — see
    /// ``AccessibilityAuditViewModel/visibleGroups`` — because a section of findings sitting under
    /// a switch that is off reads as a switch that did nothing. Switching one *on* cannot conjure
    /// findings, so it says so here instead of quietly leaving a report that has never looked for
    /// them.
    private var awaitingRerunBanner: some View {
        Section {
            Label(awaitingRerunDescription, systemImage: "arrow.clockwise")
                .foregroundStyle(.orange)
        }
    }

    /// The wording for a check switched on since the pass: which one, and what to do about it.
    ///
    /// Names the **Re-run** button through ``localized(_:comment:)`` rather than spelling it out,
    /// for the same reason ``coveredDescription`` names the live toggle that way: a developer
    /// reading Scyther in German should be pointed at the German button in the toolbar above.
    private var awaitingRerunDescription: String {
        let names = ListFormatter.localizedString(byJoining: viewModel.checksAwaitingRerun.map(\.title))
        let rerun = localized("Re-run")
        return localized("\(names) switched on after this report was run. Tap \(rerun) to include it.")
    }

    // MARK: - Findings

    /// One section per check with at least one finding, headed by the check's name and, for
    /// contrast, footed by a note that its ratios are estimates rather than exact measurements.
    ///
    /// - Parameter group: The check and its findings to show.
    private func findingsSection(for group: AccessibilityAuditViewModel.Group) -> some View {
        Section {
            ForEach(group.findings) { finding in
                Button {
                    viewModel.flash(finding)
                } label: {
                    findingRow(finding)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(group.check.title)
        } footer: {
            if group.check == .contrast {
                Text(localized("Contrast ratios are estimated by sampling pixels on screen, not measured from exact colors."))
            }
        }
    }

    /// One finding: a severity dot, the element it was found on, and the measurement that
    /// explains why it was flagged — the two-line title-over-subtitle shape the rest of Scyther's
    /// menu uses (see `MenuView.searchResultLabel`), not `LabeledContent`, which would render
    /// both lines at the same weight and read as two titles rather than a title and its detail.
    ///
    /// - Parameter finding: The finding to show.
    private func findingRow(_ finding: AccessibilityFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            severityDot(finding.severity)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.elementName)
                Text(finding.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// A small filled circle in the finding's severity colour, matching the colours the live
    /// overlay strokes its own boxes in — red for ``AccessibilitySeverity/error``, orange for
    /// ``AccessibilitySeverity/warning``. Not a stock SwiftUI component, so it is drawn rather
    /// than assembled from one.
    ///
    /// - Parameter severity: The finding's severity.
    private func severityDot(_ severity: AccessibilitySeverity) -> some View {
        Circle()
            .fill(severity == .error ? Color.red : Color.orange)
            .frame(width: 8, height: 8)
            .accessibilityLabel(severity == .error ? localized("Error") : localized("Warning"))
    }

    // MARK: - Empty State

    /// Shown when the current report has no findings to show.
    ///
    /// Three distinct things produce an empty ``AccessibilityAuditViewModel/visibleGroups``, and
    /// the screen leads with a different headline and a different symbol for each, because a green
    /// tick over "No Issues Found" is a claim and two of the three cannot support it:
    ///
    /// - **Nothing ran.** Every check switched off, or every check refused. Nothing on this screen
    ///   has been looked at, and the old empty state answered that with a tick.
    /// - **Something ran, but not everything.** A check switched off, a check skipped, a check that
    ///   could not be measured, or a walk the node or depth cap stopped early. The part that was
    ///   checked was clean; the rest was never reached. The old empty state said "Every enabled
    ///   check passed" here too, directly underneath the orange banner saying the walk stopped.
    /// - **Everything ran and found nothing.** The one case that has earned a tick.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                emptyStateTitle,
                systemImage: emptyStateSymbol,
                description: Text(emptyStateDescription)
            )
            .frame(maxWidth: .infinity)
            .padding()
            .listRowBackground(Color.clear)
        } else {
            VStack(spacing: 16) {
                Image(systemName: emptyStateSymbol)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(emptyStateTitle)
                    .font(.headline)
                Text(emptyStateDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .listRowBackground(Color.clear)
        }
    }

    /// The empty state's headline. See ``emptyState`` for the three cases.
    private var emptyStateTitle: String {
        if viewModel.nothingWasChecked { return localized("Nothing Was Checked") }
        if viewModel.isComplete { return localized("No Issues Found") }
        return localized("No Issues In What Was Checked")
    }

    /// The empty state's symbol.
    ///
    /// `checkmark.circle` is reserved for the one case that passed everything. The other two get
    /// `questionmark.circle`, which is what an unanswered question looks like — the point being
    /// that neither of them is a result about the app.
    private var emptyStateSymbol: String {
        viewModel.isComplete ? "checkmark.circle" : "questionmark.circle"
    }

    /// The empty state's explanation.
    ///
    /// It names the checks the developer switched off, because nothing else on the screen does.
    /// It does not name the checks Scyther skipped or could not measure, or say that the walk
    /// stopped early: ``coveredBanner``, ``unmeasurableBanner`` and ``truncatedBanner`` have each
    /// already said which and why, in more detail than belongs under a headline. What it must
    /// never do is claim more than the pass supports, which is why "every enabled check passed"
    /// appears in exactly one of these branches.
    private var emptyStateDescription: String {
        let switchedOff = viewModel.switchedOffChecks
        if viewModel.nothingWasChecked {
            guard !switchedOff.isEmpty else { return localized("No check on this screen could be run.") }
            let names = ListFormatter.localizedString(byJoining: switchedOff.map(\.title))
            return localized("No check ran. Switched off: \(names).")
        }
        if !switchedOff.isEmpty {
            let names = ListFormatter.localizedString(byJoining: switchedOff.map(\.title))
            return localized("The checks that ran found nothing to report. Switched off: \(names).")
        }
        if !viewModel.isComplete {
            return localized("The checks that ran found nothing to report.")
        }
        return localized("Every enabled check passed.")
    }
}

#Preview {
    NavigationStack {
        AccessibilityAuditView()
    }
}
#endif
