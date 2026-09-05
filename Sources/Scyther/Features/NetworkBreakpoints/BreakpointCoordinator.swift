//
//  BreakpointCoordinator.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// How a held exchange was let go.
enum BreakpointResolution: Sendable {
    /// Carry on with this draft, which may have been edited.
    case `continue`(BreakpointDraft)

    /// Do not carry on; fail the request with this error instead.
    case abort(URLError.Code)

    /// Nobody decided in time. Carry on unmodified.
    case timedOut
}

/// Where the URL loading system and the developer meet.
///
/// ``pause(_:name:stage:timeout:resume:)`` is called from `HTTPInterceptorURLProtocol`, on a
/// thread the URL loading system owns. **It does not block.** It records the draft together with
/// the continuation that resumes the exchange, publishes the pause to the main actor for the UI to
/// show, arms a timeout, and returns. The continuation runs later — on this coordinator's own
/// private serial queue — when the developer resolves the pause, when the timeout fires, or never,
/// if the request was cancelled first.
///
/// ## Why nothing blocks
///
/// An earlier draft of this design held the calling thread on a `DispatchSemaphore` until the
/// pause resolved. Two things make that wrong, and a breakpoint is where they bite hardest.
/// `startLoading()` runs on a thread the URL loading system owns, and whether that thread is
/// per-request or drawn from a shared pool is not contracted — so a held request can hold up
/// traffic that matches no breakpoint at all. And a blocked delegate queue also blocks the very
/// cancellation that would end the wait, so the app cannot get its thread back by cancelling. A
/// breakpoint may hold for five minutes, which is that hazard multiplied by ten. Nothing here
/// blocks a thread it does not own.
///
/// ## Ordering
///
/// Registration, resolution, timeout and cancellation all run on ``queue``, so they are totally
/// ordered with respect to one another. The UI cannot see a pause before its continuation is
/// registered, because the row is published from inside the block that registers it; and a
/// continuation is removed before it is called, so a pause resolves exactly once however many
/// decisions race for it.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Holding an Exchange
/// - ``pause(_:name:stage:timeout:resume:)``
/// - ``cancel(id:)``
///
/// ### Deciding
/// - ``resolve(id:with:)``
/// - ``pending``
/// - ``onPendingChanged``
final class BreakpointCoordinator: @unchecked Sendable {
    /// The coordinator the interceptor and the UI both use.
    static let shared = BreakpointCoordinator()

    /// The queue owning ``continuations`` and running every continuation.
    ///
    /// Serial, and private to the coordinator. A continuation starts a data task or hands a
    /// response to the client, so it must not run on the main actor and must not run on a queue
    /// the URL loading system owns.
    private let queue = DispatchQueue(label: "com.scyther.networkBreakpoints.coordinator",
                                      qos: .userInitiated)

    /// The continuation waiting on each live pause.
    ///
    /// - Note: Only ever touched on ``queue``.
    private var continuations: [UUID: @Sendable (BreakpointResolution) -> Void] = [:]

    /// The pauses the developer can currently see, oldest first.
    @MainActor private(set) var pending: [PendingBreakpoint] = []

    /// Called on the main actor whenever ``pending`` changes, so a presenter can show or hide the
    /// editor.
    @MainActor var onPendingChanged: (([PendingBreakpoint]) -> Void)?

    /// Creates a coordinator.
    ///
    /// - Note: Internal rather than private so a test can drive one that is not the shared
    ///   instance. Production uses ``shared``.
    init() { }

    /// Holds an exchange and returns immediately, having taken ownership of the draft.
    ///
    /// - Parameters:
    ///   - draft: The exchange as it stands, ready to be edited.
    ///   - name: The name of the breakpoint that matched, shown in the editor.
    ///   - stage: Which side of the exchange is being held.
    ///   - timeout: Seconds to hold before resuming with ``BreakpointResolution/timedOut``. Taken
    ///     as given: ``NetworkBreakpoint`` is what clamps a configured timeout into its allowed
    ///     range, and a test needs a shorter one than that range allows.
    ///   - resume: Called once, on ``queue``, with the decision. Never called at all if the pause
    ///     is cancelled first.
    /// - Returns: The pause's identifier, which ``cancel(id:)`` and ``resolve(id:with:)`` take.
    @discardableResult
    func pause(_ draft: BreakpointDraft,
               name: String,
               stage: NetworkBreakpoint.Stage,
               timeout: TimeInterval,
               resume: @escaping @Sendable (BreakpointResolution) -> Void) -> UUID {
        let id = UUID()
        let deadline = Date().addingTimeInterval(timeout)

        queue.async { [self] in
            continuations[id] = resume

            /// Armed from inside the registration so the timeout can never fire against a pause
            /// that is not registered yet.
            queue.asyncAfter(deadline: .now() + timeout) { [self] in
                deliver(.timedOut, to: id)
            }

            Task { @MainActor [self] in
                let item = PendingBreakpoint(id: id,
                                             breakpointName: name,
                                             stage: stage,
                                             draft: draft,
                                             deadline: deadline)
                pending.append(item)
                onPendingChanged?(pending)
            }
        }

        return id
    }

    /// Lets a held exchange go, with the developer's decision.
    ///
    /// The row is removed here, on the main actor, rather than waiting for the continuation to
    /// run: the developer has decided, and the editor should not sit there showing a pause that
    /// has already been let go.
    ///
    /// - Parameters:
    ///   - id: The pause to resolve.
    ///   - resolution: What to do with the exchange.
    @MainActor
    func resolve(id: UUID, with resolution: BreakpointResolution) {
        if pending.contains(where: { $0.id == id }) {
            pending.removeAll { $0.id == id }
            onPendingChanged?(pending)
        }
        queue.async { [self] in
            deliver(resolution, to: id)
        }
    }

    /// Drops a pending pause without resuming it. Called by `stopLoading()`.
    ///
    /// The continuation is discarded rather than called, because the client that would have
    /// received its callbacks has gone away, and delivering to a cancelled client is something the
    /// `URLProtocol` contract forbids.
    ///
    /// - Parameter id: The pause to drop.
    func cancel(id: UUID) {
        queue.async { [self] in
            guard continuations.removeValue(forKey: id) != nil else { return }
            Task { @MainActor [self] in
                guard pending.contains(where: { $0.id == id }) else { return }
                pending.removeAll { $0.id == id }
                onPendingChanged?(pending)
            }
        }
    }

    /// Runs the continuation for `id`, if it is still live, and takes its row away.
    ///
    /// Removing the continuation before calling it is what makes a pause resolve exactly once: a
    /// decision that races the timeout finds nothing left to resume.
    ///
    /// - Parameters:
    ///   - resolution: What to do with the exchange.
    ///   - id: The pause being resolved.
    /// - Note: Only ever called on ``queue``.
    private func deliver(_ resolution: BreakpointResolution, to id: UUID) {
        guard let resume = continuations.removeValue(forKey: id) else { return }
        Task { @MainActor [self] in
            guard pending.contains(where: { $0.id == id }) else { return }
            pending.removeAll { $0.id == id }
            onPendingChanged?(pending)
        }
        resume(resolution)
    }
}
