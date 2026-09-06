//
//  HeldRequestsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// Backs ``HeldRequestsView``: owns the navigation path over the held exchanges.
///
/// The list itself belongs to ``BreakpointPresenter``, which is the one subscriber to the
/// coordinator. This decides only what is on screen: a single held exchange opens its editor
/// straight away, because a list of one row in front of a paused app is a tap that teaches
/// nothing, and a pause that has been resolved elsewhere — by its timeout, or by a cancelled
/// request — takes its editor with it rather than leaving a form editing something that has gone.
///
/// ## Topics
///
/// ### The Path
/// - ``path``
/// - ``pendingChanged(_:)``
final class HeldRequestsViewModel: ViewModel {
    /// The identifiers of the held exchanges currently pushed, innermost last.
    @Published var path: [UUID] = []

    /// Brings the path back in line with what is actually held.
    ///
    /// - Parameter pending: The held exchanges, as the presenter has them.
    func pendingChanged(_ pending: [PendingBreakpoint]) {
        let live = Set(pending.map(\.id))
        path.removeAll { !live.contains($0) }

        if path.isEmpty, pending.count == 1, let only = pending.first {
            path = [only.id]
        }
    }
}
