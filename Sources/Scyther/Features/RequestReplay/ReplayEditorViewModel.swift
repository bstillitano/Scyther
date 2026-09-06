//
//  ReplayEditorViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// Backs ``ReplayEditorView``: holds the editable draft, validates it, and sends it.
///
/// Sending is deliberately unremarkable. The draft becomes an ordinary `URLRequest` on an
/// ordinary session, so the interceptor captures it exactly as it captures traffic the app makes
/// — including matching it against enabled overrides, which is why the editor says as much before
/// anything is sent. The only thing that marks it out afterwards is the provenance property
/// ``ReplayableRequest/makeURLRequest(replayOf:)`` stamps on it.
///
/// ## Topics
///
/// ### Creating a View Model
/// - ``init(capturing:session:dispatch:)``
///
/// ### The Draft
/// - ``draft``
/// - ``capture``
/// - ``isModified``
/// - ``methodSelection``
/// - ``customMethod``
///
/// ### Validation
/// - ``canSend``
/// - ``hasValidURL``
/// - ``changesServerState``
/// - ``warnings``
/// - ``requiresConfirmation``
///
/// ### Sending
/// - ``showingConfirmation``
/// - ``confirmationMessage``
/// - ``send()``
@MainActor
final class ReplayEditorViewModel: ViewModel {
    /// The verbs the method picker offers.
    static let commonMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    /// The methods that are safe to send twice, and therefore need no confirmation.
    ///
    /// Anything else — `POST`, `PATCH`, `DELETE`, or a verb the server invented — is treated as
    /// able to change state, because assuming otherwise is the expensive mistake.
    static let idempotentMethods: Set<String> = ["GET", "HEAD", "OPTIONS"]

    /// The picker's sentinel for a method that is not one of ``commonMethods``.
    ///
    /// Not a valid HTTP token, so it can never collide with a real method the picker is showing.
    static let otherMethodTag = "__scyther_other_method__"

    /// The request being replayed.
    let capture: HTTPRequest

    /// The editable copy shown in the form.
    @Published var draft: ReplayableRequest

    /// Whether the confirmation alert is showing.
    @Published var showingConfirmation: Bool = false

    /// The picker's current selection: a verb from ``commonMethods``, or ``otherMethodTag``.
    ///
    /// Writing it pushes straight through to ``draft``, so the picker and the draft can never
    /// disagree about what is going to be sent.
    @Published var methodSelection: String {
        didSet {
            guard methodSelection != oldValue else { return }
            draft.method = methodSelection == Self.otherMethodTag ? customMethod : methodSelection
        }
    }

    /// The free-text method used when the picker is on ``otherMethodTag``.
    ///
    /// Kept separately from ``draft`` so that switching to a listed verb and back does not lose
    /// what was typed here.
    @Published var customMethod: String {
        didSet {
            guard methodSelection == Self.otherMethodTag, customMethod != oldValue else { return }
            draft.method = customMethod
        }
    }

    /// The draft as the editor opened on it, for ``isModified``.
    private let original: ReplayableRequest

    /// How a built request is put on the wire.
    private let dispatch: @Sendable (URLRequest) -> Void

    /// Creates a view model for replaying `capture`.
    ///
    /// - Parameters:
    ///   - capture: The captured request to start from.
    ///   - session: The session the replay is sent through. The replay is captured by the
    ///     interceptor either way, because the interceptor is registered globally.
    ///   - dispatch: How to send the built request. Defaults to a data task on `session`. A test
    ///     passes its own so the suite can assert what would go out without touching the network.
    init(capturing capture: HTTPRequest,
         session: URLSession = .shared,
         dispatch: (@Sendable (URLRequest) -> Void)? = nil) {
        self.capture = capture
        let draft = ReplayableRequest(capturing: capture)
        self.draft = draft
        self.original = draft
        self.dispatch = dispatch ?? { session.dataTask(with: $0).resume() }

        let captured = draft.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isListed = Self.commonMethods.contains(captured)
        self.methodSelection = isListed ? captured : Self.otherMethodTag
        self.customMethod = isListed ? "" : draft.method
        super.init()
    }

    /// Whether the URL as typed can be sent. Drives the editor's inline warning.
    var hasValidURL: Bool { draft.isURLValid }

    /// Whether the draft can be sent: a non-empty method and a URL that parses.
    var canSend: Bool {
        !draft.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasValidURL
    }

    /// Whether anything has been edited since the editor opened.
    var isModified: Bool { draft.isModified(from: original) }

    /// Whether the method could change server state, and so should not be repeated blind.
    var changesServerState: Bool {
        !Self.idempotentMethods.contains(normalisedMethod)
    }

    /// Everything about this replay that will not be what the developer expects, in the order the
    /// editor states them.
    ///
    /// One list rather than several, so the overview footer and the confirmation alert cannot
    /// disagree about what the developer has been told. Empty means the replay is exactly the
    /// request on screen.
    var warnings: [String] {
        var lines: [String] = []
        if changesServerState {
            lines.append(localized("\(normalisedMethod) may change data on the server a second time."))
        }
        if draft.hasUncapturedBody {
            lines.append(localized("The original body was not text, so the log did not keep it. This replay is sent without a body."))
        }
        return lines
    }

    /// Whether sending asks for confirmation first.
    ///
    /// Anything in ``warnings`` earns a confirmation. A body the replay cannot carry counts
    /// even on a `GET`: sending something quietly different from the request on screen is worse
    /// than one extra tap.
    var requiresConfirmation: Bool { !warnings.isEmpty }

    /// The confirmation alert's message: every warning, one paragraph each.
    var confirmationMessage: String {
        warnings.joined(separator: "\n\n") // scyther:unlocalised paragraph break between localised lines
    }

    /// The method as it will appear on the wire, for the confirmation alert to name.
    var normalisedMethod: String {
        draft.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Adds an empty header row for the developer to fill in.
    func addHeader() {
        draft.headers.append(.init(name: "", value: ""))
    }

    /// Removes the header rows at `offsets`.
    ///
    /// - Parameter offsets: The rows to remove, as a `ForEach` reports them.
    func removeHeaders(at offsets: IndexSet) {
        draft.headers.remove(atOffsets: offsets)
    }

    /// Sends the draft. The response is captured by the interceptor like any app request.
    ///
    /// - Returns: The request that was sent, or `nil` when the draft could not be built — which
    ///   ``canSend`` already prevents the UI from reaching.
    @discardableResult
    func send() -> URLRequest? {
        guard let request = draft.makeURLRequest(replayOf: capture.getRandomHash() as String) else { return nil }
        dispatch(request)
        return request
    }
}
