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
        seed: { InterfaceToolkit.instance.accessibilityPassForReport() },
        run: { AccessibilityAudit.instance.auditKeyWindow(purpose: .report) }
    )

    var body: some View {
        List {
            settingsSection

            if viewModel.isRunning {
                runningSection
            }

            if viewModel.passPredatesThisScreen {
                stalePassBanner
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

            if viewModel.isHidingFindings, !viewModel.visibleGroups.isEmpty {
                hiddenFindingsBanner
            }

            if let provenance = viewModel.passProvenanceDescription {
                provenanceSection(provenance)
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
            Text(localized("Boxes missing labels and touch targets over the running app. Contrast is measured when you open this report, because it costs a snapshot of the whole screen."))
        }
    }

    // MARK: - What This Pass Measured

    /// Names the checks this pass ran and when it ran them.
    ///
    /// Live mode and the report no longer check the same things — see
    /// ``AccessibilityAudit/checksDeferredToTheReport`` — so the report has to say which of the two
    /// answers it is showing rather than leaving the reader to infer it from which sections happen
    /// to be present. It is also the only thing on the screen that dates the contrast measurement,
    /// which is the one finding on a report that can be invalidated by a scroll.
    ///
    /// - Parameter provenance: The sentence, from
    ///   ``AccessibilityAuditViewModel/passProvenanceDescription``.
    /// - Returns: The section.
    private func provenanceSection(_ provenance: String) -> some View {
        Section {
            Label(provenance, systemImage: "clock")
                .foregroundStyle(.secondary)
                .font(.footnote)
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

    // MARK: - How Old This Report Is

    /// Shown when the report is showing the live overlay's last pass rather than one of its own.
    ///
    /// That pass is always older than this screen — no pass can run while Scyther covers the app —
    /// and the poll that keeps the overlay in step cannot see a scroll, a table reload or a cell
    /// expanding, so a report opened after any of those describes rows that are no longer where it
    /// says they are. The age is drawn with `Text(_:style:)` rather than formatted once, so it keeps
    /// counting up while the developer reads, and through stock `LabeledContent` so it reads as a
    /// measurement rather than as a second sentence.
    private var stalePassBanner: some View {
        Section {
            Label(viewModel.stalePassDescription, systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            if let takenAt = viewModel.passTakenAt {
                LabeledContent(localized("Measured")) {
                    Text(takenAt, style: .relative)
                }
            }
        }
    }

    // MARK: - Truncated Walk

    /// Shown when ``AccessibilityAuditViewModel/didHitLimit`` is true: the walk that produced
    /// this report stopped before it finished, so the report is not necessarily the whole
    /// picture. Presenting a truncated result with no warning would tell a developer their
    /// screen is clean when the audit simply never reached the rest of it.
    ///
    /// The wording lives on the view model — see
    /// ``AccessibilityAuditViewModel/truncationDescription`` — because it is a claim about what a
    /// pass did, and a claim about a pass should be testable without rendering a view.
    private var truncatedBanner: some View {
        Section {
            Label(viewModel.truncationDescription, systemImage: "exclamationmark.triangle")
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
            Label(viewModel.coveredDescription, systemImage: "eye.slash")
                .foregroundStyle(.orange)
        }
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
            Label(viewModel.unmeasurableDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
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
            Label(viewModel.awaitingRerunDescription, systemImage: "arrow.clockwise")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Findings The Toggles Are Hiding

    /// Shown when the frozen report is holding findings back because their check has since been
    /// switched off, and there are still other findings on screen.
    ///
    /// Without it the report simply went from seven rows to two with nothing saying why, which
    /// reads as a report that found two things. The all-hidden case is not covered here — the empty
    /// state says it instead, in the same words — because a banner and an empty state stacked one
    /// above the other would say it twice.
    private var hiddenFindingsBanner: some View {
        Section {
            Label(viewModel.hiddenFindingsDescription, systemImage: "eye.slash")
                .foregroundStyle(.orange)
        }
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
    /// Four distinct things produce an empty ``AccessibilityAuditViewModel/visibleGroups``, and the
    /// screen leads with a different headline and a different symbol for each — see
    /// ``AccessibilityAuditViewModel/emptyStateDescription``, which owns the wording, because what
    /// a report may claim about a pass is a question about the pass rather than about the layout.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                viewModel.emptyStateTitle,
                systemImage: viewModel.emptyStateSymbol,
                description: Text(viewModel.emptyStateDescription)
            )
            .frame(maxWidth: .infinity)
            .padding()
            .listRowBackground(Color.clear)
        } else {
            VStack(spacing: 16) {
                Image(systemName: viewModel.emptyStateSymbol)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(viewModel.emptyStateTitle)
                    .font(.headline)
                Text(viewModel.emptyStateDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .listRowBackground(Color.clear)
        }
    }
}

#Preview {
    NavigationStack {
        AccessibilityAuditView()
    }
}
#endif
