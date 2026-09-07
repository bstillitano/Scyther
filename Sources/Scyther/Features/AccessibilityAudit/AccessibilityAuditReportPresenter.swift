//
//  AccessibilityAuditReportPresenter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

#if !os(macOS)
import SwiftUI
import UIKit

/// Puts the accessibility audit's report in front of the developer when they tap the live
/// overlay's count pill.
///
/// The pill is drawn over the running app, not inside Scyther's menu, so there is no navigation
/// stack for it to push onto: the report has to be presented over whatever the app happens to be
/// showing. That is exactly what ``BreakpointPresenter`` already does for the held-request editor,
/// and this follows it deliberately — the same anchor (`Scyther.topViewController`), the same
/// refusal to present over an anchor that is leaving or already busy, the same
/// injected-closure seam so a test can drive the decision without a real presentation, and the
/// same re-reading of UIKit's own answer rather than trusting a flag.
///
/// It is simpler than `BreakpointPresenter` in two ways, both because nothing is waiting on this
/// screen. There is no retry: a refused presentation is a tap that did nothing, and the developer
/// can tap the pill again, where a refused breakpoint editor leaves an app paused behind nothing.
/// And there is no dismissal to drive: the report is an ordinary sheet the developer swipes away
/// or closes, so the only thing this type has to do about a dismissal is notice it has happened —
/// see ``revalidatePresentation()`` — before deciding whether the next tap should present again.
///
/// Live mode keeps running throughout. Nothing here touches ``AccessibilityAudit/liveEnabled``, so
/// closing the report leaves the developer back in the app with the overlay still drawing.
///
/// ## Topics
/// ### Shared Instance
/// - ``shared``
///
/// ### Opening the Report
/// - ``openReport()``
///
/// ### Injection Points
/// - ``presentReport``
@MainActor
internal final class AccessibilityAuditReportPresenter {
    /// The presenter `InterfaceToolkit` wires the pill to.
    static let shared = AccessibilityAuditReportPresenter()

    /// How the report is put on screen. Replaced by a test.
    ///
    /// Returns whether the report actually reached the screen, for the reason
    /// ``BreakpointPresenter/presentEditor`` returns the same thing: a presentation that did not
    /// happen must say so, or this presenter spends the rest of the session believing a screen is
    /// up and refusing to open the one the developer keeps asking for.
    var presentReport: @MainActor (AccessibilityAuditReportPresenter) -> Bool = {
        $0.presentOverKeyWindow()
    }

    /// The controller currently presented, or `nil` when nothing is on screen.
    ///
    /// Held strongly, and cleared in ``revalidatePresentation()``, which asks the controller itself
    /// whether it is still presented — a reference that had been let go could not be asked.
    ///
    /// - Note: `internal` rather than `private` so a test can stand a controller in it. There is no
    ///   other way to reach the release path: the seam a test replaces to avoid presenting for real
    ///   is the very thing that would otherwise put a controller here.
    internal var hostingController: UIViewController?

    /// Whether the report reached the screen and is still expected to be on it.
    ///
    /// Set from the outcome of the presentation rather than from the intention to present, so a
    /// refused presentation does not lock the pill out for good.
    private(set) var isPresenting: Bool = false

    /// Whether the report this presenter put up is still on screen. Replaced by a test.
    ///
    /// A presentation UIKit accepted has a presenting view controller for exactly as long as it is
    /// up, so this is the honest question to ask. With no controller to ask — which is the case
    /// under an injected ``presentReport`` — the answer is "still presented", because a test that
    /// never presented anything for real has nothing that could have been dismissed.
    internal var isReportStillPresented: @MainActor (AccessibilityAuditReportPresenter) -> Bool = {
        $0.hostingController.map { $0.presentingViewController != nil } ?? true
    }

    /// The subscription that notices the report has been dismissed. See ``init()``.
    ///
    /// `nonisolated(unsafe)` only so ``deinit`` — which is not main-actor isolated — can hand the
    /// token back to `NotificationCenter`. Nothing else touches it after `init`, and the token is
    /// opaque: it is never read, only unregistered.
    private nonisolated(unsafe) var coverageObserver: NSObjectProtocol?

    /// Creates a presenter, subscribed to the one signal that says the report has gone.
    ///
    /// The report is an ordinary sheet: the developer swipes it away and nothing tells this type.
    /// Asking only on the next tap of the pill was enough to make the *next* presentation correct,
    /// but it left the whole dismissed screen — the hosting controller, its SwiftUI view graph, its
    /// view model and every finding in it — alive for as long as nobody tapped the pill again,
    /// which after switching live mode off is forever.
    ///
    /// ``ScytherPresentation/coverageDidChangeNotification`` is that signal, and it already exists:
    /// every ``ScytherHostingController`` posts it when it disappears, including on a swipe. It is
    /// not a dismissal notification — it fires for Scyther's menu as well — which is why the answer
    /// still comes from ``isReportStillPresented`` rather than from the notification's arrival.
    init() {
        // `queue: nil` rather than `.main`: the notification is only ever posted from
        // `ScytherPresentation.coverageDidChange()`, which is main-actor isolated, and a `nil`
        // queue delivers on the posting thread rather than scheduling an operation. That keeps the
        // release on the same turn as the dismissal — and makes `MainActor.assumeIsolated` below a
        // statement of fact rather than a hope.
        coverageObserver = NotificationCenter.default.addObserver(
            forName: ScytherPresentation.coverageDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.revalidatePresentation()
            }
        }
    }

    deinit {
        if let coverageObserver {
            NotificationCenter.default.removeObserver(coverageObserver)
        }
    }

    /// Opens the report, unless it is already open.
    ///
    /// Called from ``AccessibilityAuditOverlayView/onOpenReport``, which
    /// `InterfaceToolkit.setupAccessibilityAudit()` wires to this. A second tap while the report
    /// is up does nothing: UIKit would accept a second presentation over the first and leave the
    /// developer two identical reports deep with two dismissals to get back to the app.
    func openReport() {
        revalidatePresentation()
        guard !isPresenting else { return }
        isPresenting = presentReport(self)
    }

    /// Forgets — and releases — a presentation the developer has already dismissed.
    ///
    /// Reached from two places. The subscription set up in ``init()`` runs it whenever a Scyther
    /// screen disappears, which is what stops a dismissed report being retained for the rest of the
    /// process. ``openReport()`` runs it again before deciding whether to present, because that
    /// decision must not be made on a stale answer and asking twice costs one property read.
    ///
    /// Does nothing when the report was put up by an injected ``presentReport``, which is what a
    /// test does: there is no hosting controller to ask, and ``isReportStillPresented`` answers
    /// accordingly.
    private func revalidatePresentation() {
        guard isPresenting else { return }
        guard !isReportStillPresented(self) else { return }

        hostingController = nil
        isPresenting = false
    }

    /// Presents the report over the topmost view controller, and reports whether it got there.
    ///
    /// The same `UIHostingController` path `Scyther.showMenu(from:)` and ``BreakpointPresenter``
    /// use, over the same key window, so the report appears in front of the app whether or not
    /// Scyther's menu is already open. It is hosted in a ``ScytherHostingController`` rather than
    /// a plain one so the audit itself can tell that Scyther is covering the screen and skip the
    /// contrast check instead of measuring the app through this sheet's own dimming.
    ///
    /// Two things stop the presentation happening at all, and UIKit reports neither as an error:
    /// there may be no key window to anchor to, and the anchor may already be presenting something
    /// or be on its way off screen. The outcome is therefore read back off the controller, because
    /// a presentation UIKit accepts has a presenting view controller from the moment it is
    /// accepted, and one it refuses never does.
    ///
    /// - Returns: Whether the report is now on screen.
    private func presentOverKeyWindow() -> Bool {
        guard let presenter = Scyther.topViewController else {
            logMessage("Accessibility report could not be opened: no key window to anchor to.")
            return false
        }

        guard !presenter.isBeingDismissed, presenter.viewIfLoaded?.window != nil else {
            logMessage("Accessibility report could not be opened: the anchor is on its way off screen. Tap the pill again.")
            return false
        }

        let controller = ScytherHostingController(rootView: AccessibilityAuditReportSheet())
        presenter.present(controller, animated: true)

        guard controller.presentingViewController != nil else {
            logMessage("Accessibility report could not be opened: the anchor is already presenting something. Tap the pill again.")
            return false
        }

        hostingController = controller
        return true
    }
}
#endif
