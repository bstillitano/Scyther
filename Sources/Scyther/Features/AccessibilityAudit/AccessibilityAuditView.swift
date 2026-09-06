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
    @StateObject private var viewModel = AccessibilityAuditViewModel {
        AccessibilityAudit.instance.auditKeyWindow()
    }

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

            if viewModel.groups.isEmpty {
                // Only once there is an answer: an empty report during a pass would say "No
                // Issues Found" about a screen nothing has looked at yet.
                if !viewModel.isRunning {
                    emptyState
                }
            } else {
                ForEach(viewModel.groups) { group in
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

    /// Shown when the current report has no findings.
    ///
    /// "No findings" and "nothing was looked at" must not read the same way: when
    /// ``AccessibilityAuditViewModel/skippedChecks`` is not empty, ``emptyStateDescription``
    /// names exactly which checks did not run, rather than letting an empty list of findings be
    /// mistaken for a screen that passed everything.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Issues Found"),
                systemImage: "checkmark.circle",
                description: Text(emptyStateDescription)
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Issues Found"))
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

    /// The empty state's explanation: that every enabled check passed, or — when something did
    /// not run — that the checks which did run found nothing.
    ///
    /// Three cases rather than two. A check the developer switched off is named here, because
    /// nothing else on the screen says so. A check skipped because Scyther was covering the app
    /// is *not* named here: ``coveredBanner`` has already said which, and why, in more detail than
    /// belongs in an empty state — but "every enabled check passed" would still be untrue while
    /// one of them never ran, so that wording is withheld too.
    private var emptyStateDescription: String {
        if !viewModel.skippedChecks.isEmpty {
            let names = ListFormatter.localizedString(byJoining: viewModel.skippedChecks.map(\.title))
            return localized("The checks that ran found nothing to report. Switched off: \(names).")
        }
        if !viewModel.checksSkippedWhileCovered.isEmpty {
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
