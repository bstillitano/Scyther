//
//  HeldRequestEditorViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// Backs ``HeldRequestEditorView``: holds the editable copy of a paused exchange and resolves it.
///
/// The copy lives here rather than on ``PendingBreakpoint`` so that abandoning the editor — or
/// letting the timeout take it — passes on the exchange exactly as it arrived. "Continue without
/// changes" is then not a promise the editor has to keep by hand; it is a different value.
///
/// ## Topics
///
/// ### Creating an Editor
/// - ``init(pending:coordinator:)``
///
/// ### The Held Exchange
/// - ``pending``
/// - ``draft``
/// - ``title``
/// - ``isRequest``
/// - ``isEdited``
///
/// ### Editing
/// - ``method``
/// - ``url``
/// - ``statusCode``
/// - ``bodyText``
/// - ``addHeader()``
/// - ``removeHeaders(at:)``
///
/// ### Deciding
/// - ``continueWithEdits()``
/// - ``continueUnchanged()``
/// - ``abort(with:)``
/// - ``abortCodes``
/// - ``showingAbortOptions``
///
/// ### The Countdown
/// - ``remainingText(at:)``
final class HeldRequestEditorViewModel: ViewModel {
    /// The errors the abort alert offers.
    ///
    /// Four rather than every code `URLError` defines: these are the failures an app is actually
    /// written to handle, and a list of ninety would be a scroll view inside an alert.
    static let abortCodes: [URLError.Code] = [
        .cancelled,
        .timedOut,
        .notConnectedToInternet,
        .badServerResponse
    ]

    /// The pause being decided.
    let pending: PendingBreakpoint

    /// The editable copy of the held exchange.
    @Published var draft: BreakpointDraft

    /// Whether the abort alert is showing.
    @Published var showingAbortOptions: Bool = false

    /// Where the decision is delivered.
    private let coordinator: BreakpointCoordinator

    /// Creates the editor.
    ///
    /// - Parameters:
    ///   - pending: The pause being decided.
    ///   - coordinator: Where the decision is delivered. Defaults to the shared coordinator.
    init(pending: PendingBreakpoint, coordinator: BreakpointCoordinator = .shared) {
        self.pending = pending
        self.draft = pending.draft
        self.coordinator = coordinator
        super.init()
    }

    /// The screen's title: which side of the exchange is being held.
    var title: String {
        isRequest ? localized("Held Request") : localized("Held Response")
    }

    /// Whether this is a request. A response has a status code instead of a method and a URL.
    var isRequest: Bool { pending.stage == .request }

    /// Whether anything has been changed since the exchange was held.
    var isEdited: Bool { draft != pending.draft }

    // MARK: - Fields

    /// The method, as the picker-free text field reads and writes it.
    ///
    /// A free field rather than a picker: a held request already has a method, the developer is
    /// changing it rather than choosing one, and an app is entitled to a verb no picker lists.
    var method: String {
        get { draft.method ?? "" }
        set { draft.method = newValue }
    }

    /// The methods the picker offers.
    ///
    /// The standard seven, plus whatever the held request actually carried when that is something
    /// else — a captured `PROPFIND` stays `PROPFIND` rather than being quietly turned into a `GET`
    /// by a picker that could not represent it.
    var selectableMethods: [String] {
        let standard = NetworkRuleEditorViewModel.availableMethods
        let current = method
        guard !current.isEmpty, !standard.contains(current) else { return standard }
        return [current] + standard
    }

    /// The URL, as typed.
    var url: String {
        get { draft.url ?? "" }
        set { draft.url = newValue }
    }

    /// The status code, for a held response.
    var statusCode: Int {
        get { draft.statusCode ?? 200 }
        set { draft.statusCode = newValue }
    }

    /// Whether the URL as typed can be sent. Drives the editor's inline warning.
    var hasValidURL: Bool { draft.isURLValid }

    /// The body as editable text.
    ///
    /// Only ever read while ``BreakpointDraft/isBodyEditable`` is true, so the fallback is
    /// unreachable rather than lossy.
    var bodyText: String {
        get { draft.bodyText ?? "" }
        set { draft.setBodyText(newValue) }
    }

    /// The body's size, as the body row shows it.
    var bodySummary: String {
        localized("\(draft.bodyByteCount) bytes")
    }

    /// Adds an empty header row for the developer to fill in.
    func addHeader() {
        draft.headers.append(BreakpointDraft.Header(name: "", value: ""))
    }

    /// Removes the header rows at `offsets`.
    ///
    /// - Parameter offsets: The rows to remove, as a `ForEach` reports them.
    func removeHeaders(at offsets: IndexSet) {
        draft.headers.remove(atOffsets: offsets)
    }

    // MARK: - Deciding

    /// Lets the exchange go, carrying whatever has been edited.
    func continueWithEdits() {
        coordinator.resolve(id: pending.id, with: .continue(draft))
    }

    /// Lets the exchange go exactly as it arrived.
    ///
    /// Resolves with the *held* draft rather than the edited one, so this stays true however much
    /// has been typed into the form.
    func continueUnchanged() {
        coordinator.resolve(id: pending.id, with: .continue(pending.draft))
    }

    /// Fails the exchange with the error the app will see.
    ///
    /// - Parameter code: The `URLError` code to raise.
    func abort(with code: URLError.Code) {
        coordinator.resolve(id: pending.id, with: .abort(code))
    }

    /// How long is left before the exchange continues on its own.
    ///
    /// - Parameter now: The moment to measure from, supplied by the countdown's `TimelineView`.
    /// - Returns: The remaining seconds, spelled out in the reader's locale.
    func remainingText(at now: Date) -> String {
        NetworkBreakpoint.secondsText(pending.remaining(at: now))
    }
}

internal extension URLError.Code {
    /// The localised label shown in the abort alert.
    ///
    /// Only ``HeldRequestEditorViewModel/abortCodes`` are named; anything else falls back to the
    /// raw code, which is what a developer would look up anyway.
    var abortTitle: String {
        switch self {
        case .cancelled: return localized("Cancelled")
        case .timedOut: return localized("Timed Out")
        case .notConnectedToInternet: return localized("Not Connected")
        case .badServerResponse: return localized("Bad Server Response")
        default: return "\(rawValue)"
        }
    }
}
