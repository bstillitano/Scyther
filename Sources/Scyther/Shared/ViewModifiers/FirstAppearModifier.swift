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
    /// Two first appearances from the same call site never run at the same time. A `@State` flag
    /// alone could not promise that: SwiftUI is free to discard and re-create a view, the
    /// re-created copy gets a fresh `false`, and its `.task` then runs the action again on top of
    /// the one still suspended. That is exactly what happens when something is presented over a
    /// screen — and if the action is what triggered the presentation, the two feed each other.
    ///
    /// A second appearance is **queued, not dropped**. It waits for the one in flight and then
    /// runs its own action. Dropping it would be worse than the bug: SwiftUI discarded the first
    /// view, and with it the `@StateObject` its action was loading, so the model the developer is
    /// actually looking at belongs to the *second* view — refusing it outright leaves that screen
    /// unloaded for good. See ``FirstAppearGuard``.
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

/// Serialises first-appear actions, so that two never run at the same time from one call site.
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
/// of the actions currently running.
///
/// ## Queued, not refused
///
/// A caller that finds the key taken **waits and then runs**. It is tempting to refuse it
/// instead, and that is a worse bug than the one this fixes: the premise of the whole thing is
/// that SwiftUI *discarded* the first view, and a discarded view takes its `@StateObject` with
/// it. The action still in flight is therefore loading a model nothing is rendering, and the
/// model on screen belongs to the caller being refused. Refusing turns "the screen loads twice"
/// into "the screen never loads", which at least the original bug did not do.
///
/// Serialising is enough on its own, because what made the menu unusable was *concurrency*: each
/// overlapping run issued its own request, and each request was held. One at a time, with the
/// screens that have gone away dropping out of the queue, is a bounded queue of live views.
///
/// ## What ends a wait
///
/// Three things, in the order they are checked:
///
/// - the incumbent finishing, which is the ordinary case;
/// - the waiter's own `.task` being cancelled, which means its view has gone away — it stops
///   waiting and does not run at all, so the queue prunes itself to the views still on screen;
/// - ``maximumWait`` elapsing. Swift cancellation is cooperative and an action is free to ignore
///   it — `NetworkHelper.ipAddress` does, which is exactly why the discarded menu's fetch stayed
///   in flight — so an action that never returns would otherwise hold its key for the life of the
///   process and that screen could never load again. The deadline bounds the damage to a wait
///   rather than a brick, at the cost of allowing a second action alongside one that has clearly
///   hung, which is the right way round.
///
/// The wait is a poll rather than a queue of continuations. A continuation queue has to resume
/// exactly once per waiter across cancellation, timeout and the ordinary path, and resuming one
/// twice is a crash; the poll is a `while` loop with three exits, it only runs while something is
/// genuinely waiting, and this is a feature that has already shipped one subtle bug.
///
/// ## What identifies an action
///
/// A `#fileID`/`#line`/`#column` triple: stable across a view being re-created, and distinct for
/// every `.onFirstAppear` in the codebase. Two views that share one call site and are on screen
/// together share an entry, which is what ``View/onFirstAppear(id:_:fileID:line:column:)``'s `id`
/// parameter is for — and there are two such call sites, `FileBrowserView` and `LogDetailsView`,
/// both of which push themselves to arbitrary depth. Both pass one.
///
/// Membership is released when the action finishes rather than kept forever, so a screen
/// genuinely left and returned to still loads.
///
/// - Note: `@MainActor` throughout, which is what makes claim-then-run atomic: the wait ends and
///   the key is taken in one main-actor step, with no suspension in between for another caller to
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

    /// The longest a queued first appearance waits for the one in flight before going ahead
    /// anyway.
    ///
    /// Long enough that no first-appear anyone would write reaches it, short enough that an
    /// action which never returns costs a wait rather than a screen that can never load again.
    ///
    /// - Note: Internal and settable so a test can observe the bound without waiting a minute for
    ///   it. Nothing in production changes it.
    internal var maximumWait: TimeInterval = 60

    /// How often a waiter re-checks. Small enough to be invisible on screen, large enough that
    /// waiting costs nothing — and nothing waits unless a first appearance is genuinely in
    /// flight.
    private static let pollInterval: UInt64 = 20_000_000

    /// Creates the guard.
    ///
    /// - Note: Internal rather than private, so a test can drive an instance of its own instead
    ///   of the process-wide one.
    internal init() { }

    /// Waits for any first appearance already running for `key`, then runs `action`.
    ///
    /// - Parameters:
    ///   - key: What identifies this first-appear.
    ///   - action: The work to run.
    /// - Returns: Whether the action ran. `false` means the caller was cancelled while waiting —
    ///   its view has gone away — so running would only have loaded a model nobody is rendering.
    @discardableResult
    func run(_ key: Key, action: () async -> Void) async -> Bool {
        guard await waitForTurn(key) else { return false }

        running.insert(key)
        defer { running.remove(key) }

        await action()
        return true
    }

    /// Waits until nothing is running for `key`, this caller is cancelled, or ``maximumWait``
    /// elapses.
    ///
    /// - Parameter key: The first-appear to wait for.
    /// - Returns: Whether the caller should go ahead and run. `false` only for a cancelled
    ///   caller.
    private func waitForTurn(_ key: Key) async -> Bool {
        guard running.contains(key) else { return true }

        let deadline = Date().addingTimeInterval(maximumWait)
        while running.contains(key) {
            if Task.isCancelled { return false }
            if Date() >= deadline { return true }
            try? await Task.sleep(nanoseconds: Self.pollInterval)
        }
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
/// reload. ``FirstAppearGuard`` stops two runs overlapping when SwiftUI replaces the view with a
/// fresh copy while the action is still suspended, which `@State` cannot see because the fresh
/// copy has a fresh flag.
///
/// The flag is committed before the guard is asked, and that is deliberate: the guard queues
/// rather than refuses, so every appearance that gets this far does eventually run its action.
/// The one case it does not — a waiter cancelled because its view went away — is a view that no
/// longer needs loading.
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
