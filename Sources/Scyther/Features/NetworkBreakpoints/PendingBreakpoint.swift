//
//  PendingBreakpoint.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// One request or response held mid-flight, awaiting a decision.
///
/// A reference type, so the same pause can be identified across the pending list and the editor
/// without copying, and main-actor isolated, because it exists to be shown.
///
/// What it carries is deliberately immutable. The editable copy lives on
/// ``HeldRequestEditorViewModel``, which is what the developer types into and what the resolution
/// carries back; this is the exchange as it was held, which is what "continue without changes"
/// means and what the log compares against to decide whether anything was edited.
///
/// The exchange itself is not here either. The continuation that resumes it belongs to
/// ``BreakpointCoordinator``, keyed by ``id``, so nothing on the main actor can hold a request
/// open by holding this object.
@MainActor
final class PendingBreakpoint: Identifiable {
    /// The identifier the coordinator resolves this pause by.
    let id: UUID

    /// The name of the breakpoint that held the exchange, for the editor's title.
    let breakpointName: String

    /// Which side of the exchange is being held.
    let stage: NetworkBreakpoint.Stage

    /// The exchange as it was held.
    let draft: BreakpointDraft

    /// When the pause continues on its own, unmodified.
    let deadline: Date

    /// Creates a pending breakpoint.
    ///
    /// - Parameters:
    ///   - id: The identifier the coordinator resolves this pause by.
    ///   - breakpointName: The name of the breakpoint that held the exchange.
    ///   - stage: Which side of the exchange is held.
    ///   - draft: The exchange as it was held.
    ///   - deadline: When the pause continues on its own.
    init(id: UUID,
         breakpointName: String,
         stage: NetworkBreakpoint.Stage,
         draft: BreakpointDraft,
         deadline: Date) {
        self.id = id
        self.breakpointName = breakpointName
        self.stage = stage
        self.draft = draft
        self.deadline = deadline
    }

    /// Seconds left before the pause continues on its own, never below zero.
    ///
    /// - Parameter now: The moment to measure from, which the countdown's `TimelineView` supplies
    ///   so that the view is a function of the time it was handed rather than of the clock.
    /// - Returns: The remaining seconds.
    func remaining(at now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }
}
