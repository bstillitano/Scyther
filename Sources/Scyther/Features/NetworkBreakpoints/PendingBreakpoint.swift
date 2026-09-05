//
//  PendingBreakpoint.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// One request or response held mid-flight, awaiting a decision.
///
/// A reference type rather than a value: the editor binds straight to ``draft`` and every field it
/// changes has to reach the same object the coordinator will read back when the developer
/// continues. It lives on the main actor for the same reason — it exists to be edited.
///
/// The exchange itself is not here. The continuation that resumes it belongs to
/// ``BreakpointCoordinator``, keyed by ``id``, so nothing on the main actor can hold a request
/// open by holding this object.
@MainActor
final class PendingBreakpoint: Identifiable, ObservableObject {
    /// The identifier the coordinator resolves this pause by.
    let id: UUID

    /// The name of the breakpoint that held the exchange, for the editor's title.
    let breakpointName: String

    /// Which side of the exchange is being held.
    let stage: NetworkBreakpoint.Stage

    /// When the pause continues on its own, unmodified.
    let deadline: Date

    /// The editable copy of the held exchange.
    @Published var draft: BreakpointDraft

    /// The draft as it arrived, so the editor can tell whether anything was changed.
    let original: BreakpointDraft

    /// Whether anything has been edited since the pause arrived.
    var isEdited: Bool { draft != original }

    /// Creates a pending breakpoint.
    ///
    /// - Parameters:
    ///   - id: The identifier the coordinator resolves this pause by.
    ///   - breakpointName: The name of the breakpoint that held the exchange.
    ///   - stage: Which side of the exchange is held.
    ///   - draft: The editable copy of the held exchange.
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
        self.original = draft
        self.deadline = deadline
    }
}
