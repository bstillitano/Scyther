//
//  FirstAppearModifier.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/3/2024.
//

import SwiftUI

extension View {
    /// Performs an asynchronous action when the view first appears.
    ///
    /// Unlike `onAppear`, this modifier ensures the action is only called once,
    /// even if the view appears multiple times. This is useful for one-time
    /// initialization tasks like loading data.
    ///
    /// ```swift
    /// struct MyView: View {
    ///     var body: some View {
    ///         Text("Hello")
    ///             .onFirstAppear {
    ///                 await loadInitialData()
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// ## Re-entrancy
    ///
    /// The action is also guaranteed not to be started a second time while it is still running.
    /// A `@State` flag alone could not promise that: SwiftUI is free to discard and re-create a
    /// view, the re-created copy gets a fresh `false`, and its `.task` then runs the action again
    /// on top of the one still suspended. That is exactly what happens when something is
    /// presented over a screen — and if the action is what triggered the presentation, the two
    /// feed each other. See ``FirstAppearGuard`` for where the surviving half of the guard lives.
    ///
    /// - Parameters:
    ///   - id: An optional discriminator, needed only when one call site backs several views that
    ///     can be on screen at once — a row inside a `ForEach`, say. Call sites that back a single
    ///     screen, which is all of Scyther's, can leave it out.
    ///   - action: An asynchronous closure to execute when the view first appears.
    ///   - fileID: The call site's file. Defaulted; never pass this.
    ///   - line: The call site's line. Defaulted; never pass this.
    ///   - column: The call site's column. Defaulted; never pass this.
    /// - Returns: A view that triggers the action on first appearance.
    func onFirstAppear(id: AnyHashable? = nil,
                       _ action: @escaping () async -> Void,
                       fileID: String = #fileID,
                       line: UInt = #line,
                       column: UInt = #column) -> some View {
        modifier(FirstAppearModifier(action: action,
                                     key: FirstAppearGuard.Key(fileID: fileID,
                                                               line: line,
                                                               column: column,
                                                               id: id)))
    }
}

/// Tracks which first-appear actions are currently running, so that none is ever started twice.
///
/// ## Why the guard cannot live in the view
///
/// ``FirstAppearModifier`` keeps a `@State` flag, and `@State` belongs to the view: SwiftUI may
/// discard a view and build a new one for the same place in the hierarchy, and the new one starts
/// with the flag back at `false`. Its `.task` then runs the action again while the first call is
/// still suspended at an `await`.
///
/// That is not hypothetical. Presenting anything over Scyther's menu re-created the menu, whose
/// first-appear fetched the device's IP address; the fetch was held at a breakpoint, holding it
/// presented the held-request editor, presenting the editor re-created the menu, and the whole
/// thing went round once a second until a stack of modals had to be dismissed one by one. Fixing
/// the fetch alone would have left the same trap set for the next slow first-appear.
///
/// So the half of the guard that has to outlive the view lives here instead — a process-wide set
/// of the actions currently running. Membership is claimed before the action starts and released
/// however it ends, cancellation included.
///
/// ## What identifies an action
///
/// A `#fileID`/`#line`/`#column` triple: stable across a view being re-created, and distinct for
/// every `.onFirstAppear` in the codebase. Two views that share one call site and are on screen
/// together would share an entry, which is what ``View/onFirstAppear(id:_:fileID:line:column:)``'s
/// `id` parameter is for; every call site in Scyther backs a single screen, so none passes one.
///
/// Membership is deliberately released when the action finishes rather than kept forever. A
/// screen that is genuinely left and returned to is a new view with a new first appearance, and
/// keeping the entry would stop it ever loading again.
///
/// - Note: `@MainActor` throughout, which is what makes claim-then-run atomic: the check and the
///   insert happen in one main-actor step, with no suspension in between for another caller to
///   slip through.
@MainActor
final class FirstAppearGuard {
    /// The process-wide guard. Views have no way to share one otherwise — anything held by the
    /// view is discarded along with it, which is the problem this type exists to solve.
    static let shared = FirstAppearGuard()

    /// What identifies one first-appear action across a view being re-created.
    struct Key: Hashable {
        /// The file the `.onFirstAppear` was written in.
        let fileID: String

        /// The line it was written on.
        let line: UInt

        /// The column it was written at, so two on one line stay distinct.
        let column: UInt

        /// A caller-supplied discriminator for a call site backing several live views, or `nil`.
        let id: AnyHashable?
    }

    /// The actions currently running.
    private var running: Set<Key> = []

    /// Creates the guard. Private so that ``shared`` is the only instance in production; a test
    /// makes its own to keep the process-wide one clean.
    ///
    /// - Note: Internal rather than private, so a test can drive an instance of its own.
    internal init() { }

    /// Runs `action`, unless the same first-appear is already running.
    ///
    /// - Parameters:
    ///   - key: What identifies this first-appear.
    ///   - action: The work to run.
    /// - Returns: Whether the action was started. `false` means an earlier call is still running
    ///   it, and this one deliberately did nothing.
    @discardableResult
    func run(_ key: Key, action: () async -> Void) async -> Bool {
        guard running.insert(key).inserted else { return false }

        /// Released on every exit, including the one that matters most: the enclosing `.task`
        /// being cancelled because the view went away mid-action. Leaving the entry behind there
        /// would stop the screen ever loading again.
        defer { running.remove(key) }

        await action()
        return true
    }

    /// Whether this first-appear is running right now.
    ///
    /// - Parameter key: What identifies the first-appear.
    /// - Returns: Whether an action for it is in flight.
    /// - Note: Internal so a test can assert the entry is released once the action ends. Nothing
    ///   in production reads it.
    internal func isRunning(_ key: Key) -> Bool {
        running.contains(key)
    }
}

/// A view modifier that executes an action only on the first appearance of a view.
///
/// Two guards, because one is not enough. The `@State` flag stops the action re-running when the
/// *same* view appears again — a push and a pop — and is the reason a screen returned to does not
/// reload. ``FirstAppearGuard`` stops it re-running when SwiftUI replaces the view with a fresh
/// copy while the action is still suspended, which `@State` cannot see because the fresh copy has
/// a fresh flag.
private struct FirstAppearModifier: ViewModifier {
    let action: () async -> Void

    /// What identifies this call site to ``FirstAppearGuard``.
    let key: FirstAppearGuard.Key

    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        /// Explicitly main-actor isolated, so that `action` — which every call site writes as a
        /// call into a `@MainActor` view model — never has to cross an isolation boundary to
        /// reach ``FirstAppearGuard``, which is main-actor isolated for the same reason.
        content.task { @MainActor in
            guard !hasAppeared else { return }
            hasAppeared = true
            await FirstAppearGuard.shared.run(key, action: action)
        }
    }
}
