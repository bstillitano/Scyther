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
    /// Held strongly, and cleared only in ``revalidatePresentation()``, which asks the controller
    /// itself whether it is still presented — a reference that had been let go could not be asked.
    private var hostingController: UIViewController?

    /// Whether the report reached the screen and is still expected to be on it.
    ///
    /// Set from the outcome of the presentation rather than from the intention to present, so a
    /// refused presentation does not lock the pill out for good.
    private var isPresenting: Bool = false

    /// Creates a presenter. Production uses ``shared``; a test makes its own so one test's
    /// presentation state cannot leak into another's.
    init() { }

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

    /// Forgets a presentation the developer has already dismissed.
    ///
    /// The report is an ordinary, swipe-away sheet: it goes without telling this presenter, which
    /// would otherwise go on believing it is up and refuse every later tap on the pill. There is
    /// no single notification for "the controller I presented is no longer presented", so it is
    /// asked here, on the one path that reacts to a tap.
    ///
    /// Does nothing when the report was put up by an injected ``presentReport``, which is what a
    /// test does: there is no hosting controller to ask.
    private func revalidatePresentation() {
        guard isPresenting, let controller = hostingController else { return }
        guard controller.presentingViewController == nil else { return }

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
