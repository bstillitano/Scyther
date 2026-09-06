//
//  BreakpointPresenter.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import SwiftUI
import UIKit

/// Puts the held-request editor in front of the developer, wherever they are in the app.
///
/// A breakpoint is no use if the developer has to find it. The presenter is the single subscriber
/// to ``BreakpointCoordinator/onPendingChanged``, and it does two things with what arrives: it
/// republishes the list for ``HeldRequestsView`` to render, and it presents that view over the key
/// window the first time something is held, dismissing it once nothing is.
///
/// ## Backgrounded apps
///
/// A pause **taken** while the app is not active is skipped: that one exchange is resumed
/// unchanged and the skip is logged. A held request the developer cannot see is indistinguishable
/// from a hang, and the developer is by definition not looking at an app that is not on screen.
/// This is the one place the check can honestly be made, because `UIApplication.applicationState`
/// can only be read on the main actor and the pause is taken on a thread the URL loading system
/// owns.
///
/// Only the newly taken pause is skipped, never the whole list. `.inactive` covers Control Centre,
/// the app switcher, a system alert and iPad multitasking, all of which the developer comes
/// straight back from — and resolving every pause on the way past would discard the exchange they
/// were part-way through editing along with their edits.
///
/// Exchanges *already* held are let go when the app actually enters the background, which
/// ``applicationDidEnterBackground()`` observes. Sampling the state only when the list changes
/// would leave a single hold taken a moment before the developer switched away sitting there,
/// invisible, for the whole of its timeout.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Lifecycle
/// - ``start()``
/// - ``pending``
/// - ``applicationDidEnterBackground()``
///
/// ### Injection Points
/// - ``applicationState``
/// - ``presentEditor``
/// - ``dismissEditor``
/// - ``scheduleRetry``
@MainActor
internal final class BreakpointPresenter: ObservableObject {
    /// The presenter `Scyther.start()` wires up.
    static let shared = BreakpointPresenter()

    /// The exchanges currently held, oldest first.
    @Published private(set) var pending: [PendingBreakpoint] = []

    /// The coordinator this presenter watches, and that its editors resolve against.
    let coordinator: BreakpointCoordinator

    /// How the app's state is read. Replaced by a test.
    var applicationState: @MainActor () -> UIApplication.State = { UIApplication.shared.applicationState }

    /// How the editor is put on screen. Replaced by a test.
    ///
    /// Returns whether the editor actually reached the screen. A presentation that did not happen
    /// must say so: believing one did leaves the app paused behind nothing at all.
    ///
    /// The closure it is handed is called once the editor has finished appearing. UIKit ignores a
    /// dismissal asked for while a presentation is still animating, and the exchange that put the
    /// screen up can be resolved inside that window — by a timeout, or by a developer who is
    /// quick — which used to leave the screen up for good with nothing behind it. Knowing when the
    /// animation ends is what lets that dismissal be held and run afterwards.
    var presentEditor: @MainActor (BreakpointPresenter, @escaping @MainActor () -> Void) -> Bool = {
        $0.presentOverKeyWindow(whenAppeared: $1)
    }

    /// How the editor is taken off screen. Replaced by a test.
    ///
    /// The closure it is handed is called once the editor has gone. Presenting over a controller
    /// that is still on its way out is accepted by UIKit and then never appears: the exchange is
    /// held behind a screen nobody can see, and the app waits out the whole timeout. So a hold
    /// taken while the last screen is leaving waits for this instead.
    var dismissEditor: @MainActor (BreakpointPresenter, @escaping @MainActor () -> Void) -> Void = {
        $0.dismissFromKeyWindow(whenGone: $1)
    }

    /// How a refused presentation is tried again. Replaced by a test.
    ///
    /// The app is paused while a presentation cannot be made, so a refusal cannot be the end of
    /// it: the anchor is busy for a moment — a sheet dismissing, a screen still appearing — and
    /// waiting for the *next* hold means this one sits invisible for the whole of its timeout.
    var scheduleRetry: @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated { work() }
        }
    }

    /// The controller currently presented, or `nil` when nothing is on screen.
    ///
    /// Held strongly, and cleared only where this presenter knows the screen has gone:
    /// ``revalidatePresentation()`` asks the controller itself whether it is still presented, and
    /// a reference that had been let go could not be asked.
    private var hostingController: UIViewController?

    /// Whether the presentation animation is still running.
    ///
    /// UIKit silently ignores a dismissal asked for during it, so a dismissal that arrives here is
    /// remembered in ``wantsDismissal`` and run when the animation ends instead of being dropped.
    private var isAppearing: Bool = false

    /// Whether a dismissal arrived while the editor was still appearing, and is owed.
    private var wantsDismissal: Bool = false

    /// Whether a retry of a refused presentation is already booked, so a burst of holds books one
    /// rather than one apiece.
    private var isRetryScheduled: Bool = false

    /// Whether the dismissal animation is still running.
    ///
    /// Nothing is presented while it is: UIKit accepts a presentation over a controller that is
    /// leaving, and then shows nothing at all. Anything held meanwhile is put up by
    /// ``editorDidDisappear()``.
    private var isDismissing: Bool = false

    /// Whether the editor reached the screen and is still expected to be on it.
    ///
    /// Set from the outcome of the presentation rather than from the intention to present, so a
    /// refused presentation is retried the next time an exchange is held rather than swallowing
    /// every one of them. Tracked here rather than read back off UIKit on every pass, so a
    /// presentation that is still animating cannot be asked for a second time; what UIKit *can*
    /// answer — whether the controller this presenter put up is still presented — is checked by
    /// ``revalidatePresentation()``.
    private var isPresenting: Bool = false

    /// The registration for the notification ``applicationDidEnterBackground()`` answers.
    ///
    /// Held so that ``start()`` stays idempotent: `Scyther.start()` may be called more than once,
    /// and a second observer would release every held exchange twice over.
    private var backgroundObserver: NSObjectProtocol?

    /// Creates a presenter.
    ///
    /// - Parameter coordinator: The coordinator to watch. Defaults to the shared one; a test
    ///   passes its own.
    init(coordinator: BreakpointCoordinator = .shared) {
        self.coordinator = coordinator
    }

    /// Starts watching the coordinator, and the app's lifecycle. Called once, from
    /// `Scyther.start()`.
    ///
    /// Idempotent: it replaces the handler it set last time rather than adding a second one, and
    /// registers for the background notification only once.
    func start() {
        coordinator.onPendingChanged = { [weak self] items in
            self?.pendingChanged(items)
        }

        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applicationDidEnterBackground() }
        }
    }

    /// Reacts to the coordinator's list changing.
    ///
    /// - Parameter items: The exchanges currently held.
    func pendingChanged(_ items: [PendingBreakpoint]) {
        revalidatePresentation()

        guard !items.isEmpty else {
            // Anything that suggests a screen is up is enough to ask for it to come down. The
            // flag alone was not: it says only whether this presenter believes it presented, and
            // when that belief and UIKit disagree what is left is a modal listing nothing, over
            // an app waiting for nothing, with no way out — this screen offers no manual exit
            // while something is held. Dismissing when nothing is up is harmless.
            let wasHolding = !pending.isEmpty
            pending = []
            if wasHolding || hasPresentedController {
                requestDismissal()
            } else {
                isPresenting = false
            }
            return
        }

        guard applicationState() == .active else {
            /// Only what this call brought with it is skipped. Everything already held stays held:
            /// the app is behind Control Centre or the app switcher, the developer is coming
            /// straight back, and resolving the exchange they are editing would take their edits
            /// with it. What is genuinely out of sight is released by
            /// ``applicationDidEnterBackground()`` instead.
            let taken = items.filter { item in !pending.contains { $0.id == item.id } }

            /// Published before anything is resolved, because `resolve(id:with:)` calls straight
            /// back into this method on the same turn: the re-entrant call has to find these
            /// pauses already known, or it skips and logs each of them a second time.
            pending = items
            guard !taken.isEmpty else { return }

            logMessage("Breakpoint skipped: the app is not active, where a held request is indistinguishable from a hang.")
            taken.forEach { coordinator.resolve(id: $0.id, with: .continue($0.draft)) }
            return
        }

        pending = items

        // Something is held again, so a dismissal owed from the moment the list emptied is owed no
        // longer: running it once the animation ends would take the screen away from under an
        // exchange the app is waiting on.
        wantsDismissal = false

        presentIfNeeded()
    }

    /// Puts the editor up, unless it is already up or the last one is still leaving.
    ///
    /// A presentation over a controller that is on its way out is accepted and then never appears.
    /// What that leaves is the worst state this feature has: an exchange held behind a screen
    /// nobody can see, and an app that waits for the whole of the timeout with no way to tell why.
    /// ``editorDidDisappear()`` is where the wait ends.
    private func presentIfNeeded() {
        guard !isPresenting, !isDismissing, !pending.isEmpty else { return }

        isAppearing = true
        isPresenting = presentEditor(self) { [weak self] in self?.editorDidAppear() }
        guard !isPresenting else { return }

        isAppearing = false
        wantsDismissal = false
        scheduleRetryIfNeeded()
    }

    /// Books another attempt at presenting, because something is held and nothing is showing it.
    ///
    /// A refusal is nearly always momentary — the anchor is a sheet on its way out, or a screen
    /// on its way in — and the exchange behind it is an app sitting still. Retrying stops of its
    /// own accord: the hold's timeout releases it, and an empty list books nothing.
    private func scheduleRetryIfNeeded() {
        guard !isRetryScheduled, !pending.isEmpty else { return }

        isRetryScheduled = true
        scheduleRetry { [weak self] in
            guard let self else { return }
            self.isRetryScheduled = false
            self.presentIfNeeded()
        }
    }

    /// Takes the screen down, or remembers to once it has finished appearing.
    ///
    /// UIKit drops a dismissal asked for while the presentation is still animating, and says
    /// nothing about having done so. The exchange that put the screen up can be resolved inside
    /// that window — a short timeout, or a developer quicker than the animation — and the dropped
    /// dismissal used to leave an empty modal over an app waiting for nothing, with no way out.
    private func requestDismissal() {
        guard !isAppearing else {
            wantsDismissal = true
            return
        }

        isPresenting = false
        isDismissing = true
        dismissEditor(self) { [weak self] in self?.editorDidDisappear() }
    }

    /// Called once the presentation animation has finished, paying whatever dismissal it held up.
    private func editorDidAppear() {
        isAppearing = false
        guard wantsDismissal else { return }
        wantsDismissal = false
        requestDismissal()
    }

    /// Called once the dismissal animation has finished, putting the editor back up if anything
    /// was held while it was leaving.
    private func editorDidDisappear() {
        isDismissing = false
        presentIfNeeded()
    }

    /// Lets go of everything still held, because the app has left the screen.
    ///
    /// ``pendingChanged(_:)`` can only sample the app's state when the coordinator's list changes,
    /// so one exchange held a moment before the developer switched away would otherwise sit there,
    /// invisible, until its timeout. Observing the lifecycle is what closes that.
    ///
    /// Backgrounding, rather than merely resigning active: an inactive app is still on screen
    /// behind Control Centre or the app switcher, and discarding a half-typed edit for a glance at
    /// either would be worse than holding on a moment longer.
    ///
    /// - Note: Internal rather than private so a test can drive it without posting a notification
    ///   and hoping. `Scyther.start()` wires it to
    ///   `UIApplication.didEnterBackgroundNotification`.
    func applicationDidEnterBackground() {
        let held = pending
        guard !held.isEmpty else { return }

        logMessage("Breakpoints skipped: the app has been backgrounded, where a held request is indistinguishable from a hang.")

        /// `pending` is deliberately left as it stands. `resolve(id:with:)` calls back into
        /// ``pendingChanged(_:)`` on the same turn, which treats anything already in `pending` as
        /// known and so does not skip it a second time; each resolution trims the list on its own
        /// way through.
        held.forEach { coordinator.resolve(id: $0.id, with: .continue($0.draft)) }
    }

    // MARK: - Presentation

    /// Forgets a presentation the app has taken down from under the presenter.
    ///
    /// A host that swaps its root view controller, or a window that goes away, takes the editor
    /// with it without any of this running — leaving ``isPresenting`` claiming an editor is up
    /// that is not, after which every later hold is published to a screen nobody can see and the
    /// app sits paused for the whole of its timeout. There is no one notification for "the
    /// controller I presented is no longer presented", so it is checked here, on the one path that
    /// reacts to a hold.
    ///
    /// Does nothing when the editor was put up by an injected ``presentEditor``, which is what a
    /// test does: there is no hosting controller to ask.
    /// Drops this presenter's belief that it presented, without touching what is on screen.
    ///
    /// Exists so a test can reproduce the one state that turns this screen into a dead end: a
    /// controller UIKit is still showing that the presenter no longer counts as presented.
    func forgetPresentationForTesting() {
        isPresenting = false
    }

    /// Takes the screen down, whatever this presenter believed about it.
    ///
    /// The escape hatch behind the empty list's close button. Nothing is held, so there is
    /// nothing to lose by closing, and a modal with no rows and no exit is worse than any state
    /// this can leave behind.
    func dismiss() {
        requestDismissal()
    }

    /// Whether this presenter still has a controller it put on screen.
    ///
    /// The one question UIKit can answer honestly, and the only safe basis for deciding to
    /// dismiss.
    private var hasPresentedController: Bool {
        hostingController != nil
    }

    private func revalidatePresentation() {
        guard isPresenting, let controller = hostingController else { return }
        guard controller.presentingViewController == nil else { return }

        hostingController = nil
        isPresenting = false
    }

    /// Presents the editor over the topmost view controller, and reports whether it got there.
    ///
    /// The same `UIHostingController` path `Scyther.showMenu(from:)` uses, over the same key
    /// window, so a held request appears in front of the app whether or not Scyther's menu is
    /// already open. It refuses interactive dismissal: an exchange has to be decided, not swiped
    /// away.
    ///
    /// Two things stop the presentation happening at all, and UIKit reports neither as an error:
    /// there may be no key window to anchor to, and the anchor may already be presenting something
    /// — which is what a hold taken while the previous editor is still animating away runs into.
    /// The outcome is therefore read back off the controller, because a presentation UIKit accepts
    /// has a presenting view controller from the moment it is accepted, and one it refuses never
    /// does.
    ///
    /// - Returns: Whether the editor is now on screen.
    private func presentOverKeyWindow(whenAppeared: @escaping @MainActor () -> Void) -> Bool {
        guard let presenter = Scyther.topViewController else {
            logMessage("Breakpoint editor could not be presented: no key window to anchor to. It will be tried again while the exchange is held.")
            return false
        }

        guard !presenter.isBeingDismissed, presenter.viewIfLoaded?.window != nil else {
            logMessage("Breakpoint editor could not be presented: the anchor is on its way off screen. It will be tried again while the exchange is held.")
            return false
        }

        let controller = UIHostingController(rootView: HeldRequestsView(presenter: self))
        controller.isModalInPresentation = true
        presenter.present(controller, animated: true) {
            // UIKit runs this on the main thread; the compiler cannot see that through an
            // unisolated closure.
            MainActor.assumeIsolated { whenAppeared() }
        }

        guard controller.presentingViewController != nil else {
            logMessage("Breakpoint editor could not be presented: the anchor is already presenting something. It will be tried again while the exchange is held.")
            return false
        }

        hostingController = controller
        return true
    }

    /// Dismisses the editor, if it is on screen.
    private func dismissFromKeyWindow(whenGone: @escaping @MainActor () -> Void) {
        guard let controller = hostingController, controller.presentingViewController != nil else {
            // Nothing to take down, so nothing to wait for. Reporting it gone straight away is
            // what lets a hold taken in this state be presented rather than wait on an animation
            // that is not running.
            hostingController = nil
            return whenGone()
        }

        hostingController = nil
        controller.dismiss(animated: true) {
            // UIKit runs this on the main thread; the compiler cannot see that through an
            // unisolated closure.
            MainActor.assumeIsolated { whenGone() }
        }
    }
}
