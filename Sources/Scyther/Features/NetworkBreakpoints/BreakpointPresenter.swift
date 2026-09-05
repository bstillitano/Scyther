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
/// A pause taken while the app is not active is **skipped**: every held exchange is resumed
/// unchanged and the skip is logged. A held request the developer cannot see is indistinguishable
/// from a hang, and the developer is by definition not looking at a backgrounded app. This is the
/// one place the check can honestly be made, because `UIApplication.applicationState` can only be
/// read on the main actor and the pause is taken on a thread the URL loading system owns.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Lifecycle
/// - ``start()``
/// - ``pending``
///
/// ### Injection Points
/// - ``applicationState``
/// - ``presentEditor``
/// - ``dismissEditor``
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
    var presentEditor: @MainActor (BreakpointPresenter) -> Void = { $0.presentOverKeyWindow() }

    /// How the editor is taken off screen. Replaced by a test.
    var dismissEditor: @MainActor (BreakpointPresenter) -> Void = { $0.dismissFromKeyWindow() }

    /// The controller currently presented, or `nil` when nothing is on screen.
    private var hostingController: UIViewController?

    /// Whether the editor is on screen. Tracked here rather than read back off UIKit, so a
    /// presentation that is still animating cannot be asked for a second time.
    private var isPresenting: Bool = false

    /// Creates a presenter.
    ///
    /// - Parameter coordinator: The coordinator to watch. Defaults to the shared one; a test
    ///   passes its own.
    init(coordinator: BreakpointCoordinator = .shared) {
        self.coordinator = coordinator
    }

    /// Starts watching the coordinator. Called once, from `Scyther.start()`.
    ///
    /// Idempotent: it replaces the handler it set last time rather than adding a second one.
    func start() {
        coordinator.onPendingChanged = { [weak self] items in
            self?.pendingChanged(items)
        }
    }

    /// Reacts to the coordinator's list changing.
    ///
    /// - Parameter items: The exchanges currently held.
    func pendingChanged(_ items: [PendingBreakpoint]) {
        guard !items.isEmpty else {
            pending = []
            if isPresenting {
                isPresenting = false
                dismissEditor(self)
            }
            return
        }

        guard applicationState() == .active else {
            logMessage("Breakpoint skipped: the app is in the background, where a held request is indistinguishable from a hang.")
            items.forEach { coordinator.resolve(id: $0.id, with: .continue($0.draft)) }
            return
        }

        pending = items
        guard !isPresenting else { return }
        isPresenting = true
        presentEditor(self)
    }

    // MARK: - Presentation

    /// Presents the editor over the topmost view controller.
    ///
    /// The same `UIHostingController` path `Scyther.showMenu(from:)` uses, over the same key
    /// window, so a held request appears in front of the app whether or not Scyther's menu is
    /// already open. It refuses interactive dismissal: an exchange has to be decided, not swiped
    /// away.
    private func presentOverKeyWindow() {
        guard let presenter = Scyther.topViewController else {
            logMessage("Breakpoint editor could not be presented: no key window to anchor to.")
            return
        }

        let controller = UIHostingController(rootView: HeldRequestsView(presenter: self))
        controller.isModalInPresentation = true
        hostingController = controller
        presenter.present(controller, animated: true)
    }

    /// Dismisses the editor, if it is on screen.
    private func dismissFromKeyWindow() {
        hostingController?.dismiss(animated: true)
        hostingController = nil
    }
}
