//
//  NetworkRuleEditorViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation
import UniformTypeIdentifiers

/// Backs ``NetworkRuleEditorView``, the form used to create a request override or edit an
/// existing one.
///
/// The view model owns a ``draft`` copy of the rule and writes nothing until ``save()`` is called,
/// so abandoning the sheet leaves the store untouched. Everything the form binds to is exposed
/// here rather than reaching into ``draft`` from the view, which keeps the validation and the
/// action plumbing in a place a test can reach.
///
/// ## Composing actions
///
/// An override carries a stub, a header rewrite and a condition independently — see
/// ``NetworkRuleActions`` — so the form has a switch per action rather than one picker choosing
/// between them. Turning an action off remembers what was typed into it, so comparing two ways of
/// shaping the same endpoint never means retyping either of them.
///
/// ## Validity
///
/// ``isValid`` guards three mistakes that are easy to make and unpleasant to debug: an unnamed
/// rule (indistinguishable from every other unnamed rule in the list), a rule with no match facets
/// at all, which would silently apply to every request the app makes, and a rule that does nothing
/// to what it matches.
///
/// ## Usage
///
/// ```swift
/// let viewModel = NetworkRuleEditorViewModel(rule: nil, store: .shared)
/// viewModel.draft.name = "Empty cart"
/// viewModel.draft.match = .path("/api/cart")
/// viewModel.save()
/// ```
///
/// ## Topics
///
/// ### Creating an Editor
/// - ``init(rule:store:)``
/// - ``init(prefilled:store:)``
///
/// ### The Rule Being Edited
/// - ``draft``
/// - ``title``
/// - ``isValid``
/// - ``save()``
///
/// ### Match Fields
/// - ``availableMethods``
/// - ``isSelected(method:)``
/// - ``toggle(method:)``
/// - ``methodsSummary``
/// - ``hostText``
/// - ``hostKind``
/// - ``pathText``
/// - ``pathKind``
/// - ``patternKinds``
///
/// ### Stub Fields
/// - ``stubKind``
/// - ``statusCode``
/// - ``delay``
/// - ``bodyText``
/// - ``bodySummary``
/// - ``responseHeaders``
/// - ``mapLocalSummary``
/// - ``importMapLocalFile(from:)``
/// - ``didFailToImportFile``
/// - ``didFailToSave``
/// - ``contentType``
///
/// ### Rewrite Fields
/// - ``isRewritingHeaders``
/// - ``setHeaders``
/// - ``removedHeaders``
///
/// ### Condition Fields
/// - ``isConditioning``
/// - ``latency``
/// - ``bandwidthKBps``
/// - ``failureRate``
final class NetworkRuleEditorViewModel: ViewModel {
    /// The HTTP methods offered as match facets.
    ///
    /// Protocol tokens, deliberately not localised — `GET` reads as `GET` in every language.
    static let availableMethods: [String] = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    /// The pattern comparisons offered for the host and path fields.
    ///
    /// Listed here rather than derived from `CaseIterable` so that ``NetworkRulePattern/Kind``,
    /// a public type, does not have to grow a conformance solely to feed a `Picker`.
    static let patternKinds: [NetworkRulePattern.Kind] = [.exact, .contains, .wildcard]

    /// The rule being edited. Nothing reaches the store until ``save()`` is called.
    @Published var draft: NetworkRule

    /// The mock response body, as text. Written to disk by ``save()`` only when it has changed.
    @Published var bodyText: String

    /// The mock response's headers, as ordered editable rows.
    @Published var responseHeaders: [NetworkRuleHeaderField] {
        didSet { commitMockHeaders() }
    }

    /// The headers the rewrite sets, as ordered editable rows.
    @Published var setHeaders: [NetworkRuleHeaderField] {
        didSet { commitRewrite() }
    }

    /// The header names the rewrite removes, as ordered editable rows.
    @Published var removedHeaders: [NetworkRuleHeaderField] {
        didSet { commitRewrite() }
    }

    /// Whether the override's stored body identifier points at bytes that are not on disk.
    ///
    /// A body whose file went missing loads as `""`, which is also what ``originalBodyText`` holds,
    /// so the unchanged-body guard in ``save()`` would skip the rewrite and leave the override
    /// broken however many times it was re-saved. This makes the next save write the body
    /// regardless.
    private let isOriginalBodyMissing: Bool

    /// Whether the last save could not be written. Drives an alert; the sheet stays open.
    @Published var didFailToSave: Bool = false

    /// Whether the last picked map-local file could not be copied into the rules directory.
    ///
    /// Drives an alert. A file the developer picked and Scyther then failed to read is worth
    /// saying out loud, because the alternative is an override that silently serves nothing.
    @Published var didFailToImportFile: Bool = false

    /// Where the edited rule is written on ``save()``.
    private let store: NetworkRuleStore

    /// Whether this editor is creating a rule rather than editing one that already exists.
    private let isNewRule: Bool

    /// The body text as it was when the editor opened, so ``save()`` can tell whether the
    /// developer actually changed it and avoid writing a second copy of identical bytes.
    private let originalBodyText: String

    /// The body file the rule pointed at when the editor opened, if it pointed at one.
    ///
    /// Kept so ``save()`` can delete the file it supersedes. A body is written under a fresh
    /// identifier every time, and switching the stub away from a mock orphans it entirely, so
    /// without this the directory accumulates bodies no rule can ever reach.
    private let originalBodyID: UUID?

    /// The last stub seen of each kind.
    ///
    /// Switching the stub picker away from a kind and back again would otherwise discard
    /// everything typed into it, which is infuriating when comparing two ways of stubbing the
    /// same endpoint.
    private var rememberedStubs: [NetworkRuleStubKind: NetworkRuleStub] = [:]

    /// The rewrite as it was when its switch was last turned off.
    private var rememberedRewrite: NetworkHeaderRewrite?

    /// The condition as it was when its switch was last turned off.
    private var rememberedCondition: NetworkCondition?

    /// Creates an editor for a new or existing rule.
    ///
    /// A new rule starts constraining nothing and doing nothing, and so is invalid until it is
    /// named, given a host, path or query, and given an action — see ``isValid``. Seeding it with
    /// a method instead would let two taps produce an override matching every request of that
    /// method the app makes.
    ///
    /// - Parameters:
    ///   - rule: The rule to edit, or `nil` to create one.
    ///   - store: Where the rule is written on ``save()``. Defaults to the shared store.
    convenience init(rule: NetworkRule?, store: NetworkRuleStore = .shared) {
        let draft = rule ?? NetworkRule(
            name: "",
            isEnabled: true,
            match: NetworkRuleMatch(),
            actions: NetworkRuleActions(stub: .mock(MockResponse()))
        )
        self.init(draft: draft, isNewRule: rule == nil, store: store)
    }

    /// Creates an editor for a rule that does not exist yet but is already filled in.
    ///
    /// Saving a captured request as a mock builds a whole rule up front — matcher, status,
    /// headers and body — and then opens the editor on it. That rule carries an identifier the
    /// store has never seen, so it must be *added* on ``save()``; routing it through
    /// ``init(rule:store:)`` would treat it as an edit and update nothing at all.
    ///
    /// - Parameters:
    ///   - rule: The pre-filled rule. It is not added to `store` until ``save()`` is called.
    ///   - store: Where the rule is written on ``save()``. Defaults to the shared store.
    convenience init(prefilled rule: NetworkRule, store: NetworkRuleStore = .shared) {
        self.init(draft: rule, isNewRule: true, store: store)
    }

    /// The designated initialiser both entry points funnel through.
    ///
    /// - Parameters:
    ///   - draft: The rule the form edits.
    ///   - isNewRule: Whether ``save()`` adds the rule or updates one already in the store.
    ///   - store: Where the rule is written on ``save()``.
    private init(draft: NetworkRule, isNewRule: Bool, store: NetworkRuleStore) {
        self.store = store
        self.isNewRule = isNewRule
        self.draft = draft
        if let stub = draft.actions.stub {
            self.rememberedStubs = [stub.kind: stub]
        }
        self.rememberedRewrite = draft.actions.rewriteHeaders
        self.rememberedCondition = draft.actions.condition

        if case .mock(let mock) = draft.actions.stub {
            self.originalBodyID = mock.bodyID
        } else {
            self.originalBodyID = nil
        }

        let body: String
        if case .mock(let mock) = draft.actions.stub, let pending = mock.pendingBody {
            body = String(decoding: pending, as: UTF8.self)
            self.isOriginalBodyMissing = false
        } else if let originalBodyID, let data = store.bodyData(for: originalBodyID) {
            body = String(decoding: data, as: UTF8.self)
            self.isOriginalBodyMissing = false
        } else {
            body = ""
            self.isOriginalBodyMissing = originalBodyID != nil
        }
        self.bodyText = body
        self.originalBodyText = body

        if case .mock(let mock) = draft.actions.stub {
            self.responseHeaders = .fields(from: mock.headers)
        } else {
            self.responseHeaders = []
        }
        self.setHeaders = .fields(from: draft.actions.rewriteHeaders?.set ?? [:])
        self.removedHeaders = .fields(from: draft.actions.rewriteHeaders?.remove ?? [])

        super.init()
    }

    // MARK: - Presentation

    /// The editor's navigation title.
    var title: String {
        isNewRule ? localized("New Override") : localized("Edit Override")
    }

    /// Whether ``save()`` should be offered.
    ///
    /// A rule needs a name so it can be told apart in the list, a host, path or query so it picks
    /// out some endpoint rather than the whole app, and at least one action so that matching a
    /// request means something. A method on its own does not count as a match: an override
    /// matching every `GET` the app makes is the same hazard as one matching everything, and just
    /// as hard to diagnose once it is enabled.
    var isValid: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !draft.actions.isEmpty else { return false }
        return draft.match.hasHostPathOrQuery
    }

    // MARK: - Match

    /// Whether a method is currently part of the match.
    ///
    /// - Parameter method: An uppercased HTTP method from ``availableMethods``.
    /// - Returns: `true` when the rule is narrowed to that method.
    func isSelected(method: String) -> Bool {
        draft.match.methods.contains(method)
    }

    /// The value shown on the row that opens the method checklist.
    ///
    /// Selected methods are listed in ``availableMethods`` order rather than the set's own
    /// order, so the summary reads the same way twice running. A method the checklist does not
    /// offer — one a HAR import produced, say — is still listed, after the known ones, so the
    /// summary never hides a facet the rule is actually matching on.
    var methodsSummary: String {
        let known = Self.availableMethods.filter { draft.match.methods.contains($0) }
        let unknown = draft.match.methods.subtracting(Self.availableMethods).sorted()
        let selected = known + unknown
        return selected.isEmpty ? localized("Any method") : selected.joined(separator: ", ")
    }

    /// Adds or removes a method from the match.
    ///
    /// - Parameter method: An uppercased HTTP method from ``availableMethods``.
    func toggle(method: String) {
        if draft.match.methods.contains(method) {
            draft.match.methods.remove(method)
        } else {
            draft.match.methods.insert(method)
        }
    }

    /// The host pattern's text. Emptying it removes the host constraint entirely.
    var hostText: String {
        get { draft.match.host?.value ?? "" }
        set { draft.match.host = Self.pattern(value: newValue, kind: hostKind) }
    }

    /// How the host pattern is compared. Remembered even while ``hostText`` is empty.
    var hostKind: NetworkRulePattern.Kind {
        get { draft.match.host?.kind ?? rememberedHostKind }
        set {
            rememberedHostKind = newValue
            draft.match.host = Self.pattern(value: hostText, kind: newValue)
        }
    }

    /// The path pattern's text. Emptying it removes the path constraint entirely.
    var pathText: String {
        get { draft.match.path?.value ?? "" }
        set { draft.match.path = Self.pattern(value: newValue, kind: pathKind) }
    }

    /// How the path pattern is compared. Remembered even while ``pathText`` is empty.
    var pathKind: NetworkRulePattern.Kind {
        get { draft.match.path?.kind ?? rememberedPathKind }
        set {
            rememberedPathKind = newValue
            draft.match.path = Self.pattern(value: pathText, kind: newValue)
        }
    }

    /// The comparison to restore when ``hostText`` is typed into after being emptied.
    private var rememberedHostKind: NetworkRulePattern.Kind = .exact

    /// The comparison to restore when ``pathText`` is typed into after being emptied.
    private var rememberedPathKind: NetworkRulePattern.Kind = .exact

    /// Builds a pattern, collapsing an empty value to `nil` so a blank field places no constraint.
    ///
    /// - Parameters:
    ///   - value: The pattern text.
    ///   - kind: The comparison to use.
    /// - Returns: A pattern, or `nil` when `value` is blank.
    private static func pattern(value: String, kind: NetworkRulePattern.Kind) -> NetworkRulePattern? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NetworkRulePattern(kind: kind, value: trimmed)
    }

    // MARK: - Stub

    /// What answers the request in place of the network: nothing, a mock, or a local file.
    ///
    /// Changing it restores whatever was last configured for the new kind, rather than resetting
    /// it. Choosing ``NetworkRuleStubKind/none`` leaves the request to the network without
    /// disturbing the rewrite or the condition.
    var stubKind: NetworkRuleStubKind {
        get { draft.actions.stub?.kind ?? .none }
        set {
            guard newValue != stubKind else { return }
            if let stub = draft.actions.stub { rememberedStubs[stub.kind] = stub }
            switch newValue {
            case .none:
                draft.actions.stub = nil
            case .mock:
                draft.actions.stub = rememberedStubs[.mock] ?? .mock(MockResponse())
            case .mapLocal:
                draft.actions.stub = rememberedStubs[.mapLocal] ?? .mapLocal(MapLocalFile(relativePath: ""))
            }
            reloadResponseHeaders()
        }
    }

    /// The status code the stub returns. `200` when nothing is stubbed.
    var statusCode: Int {
        get {
            switch draft.actions.stub {
            case .mock(let mock): return mock.statusCode
            case .mapLocal(let file): return file.statusCode
            case nil: return 200
            }
        }
        set {
            switch draft.actions.stub {
            case .mock(var mock): mock.statusCode = newValue; draft.actions.stub = .mock(mock)
            case .mapLocal(var file): file.statusCode = newValue; draft.actions.stub = .mapLocal(file)
            case nil: break
            }
        }
    }

    /// The seconds the stub waits before responding. Zero when nothing is stubbed.
    ///
    /// - Note: A matching condition's latency is added to this when the response is served.
    var delay: TimeInterval {
        get {
            switch draft.actions.stub {
            case .mock(let mock): return mock.delay
            case .mapLocal(let file): return file.delay
            case nil: return 0
            }
        }
        set {
            switch draft.actions.stub {
            case .mock(var mock): mock.delay = newValue; draft.actions.stub = .mock(mock)
            case .mapLocal(var file): file.delay = newValue; draft.actions.stub = .mapLocal(file)
            case nil: break
            }
        }
    }

    /// A one-line description of the mock body, shown on the row that opens the body editor.
    var bodySummary: String {
        bodyText.isEmpty ? localized("Not set") : localized("\(bodyText.utf8.count) bytes")
    }

    /// The name of the file a map-local stub serves, or a placeholder while none is chosen.
    ///
    /// The copy on disk is named after an identifier so it can be swept like a mock body, so the
    /// name of the document it was made from is what the row shows. A path supplied from code
    /// carries no such name, and falls back to the file name on the end of that path.
    var mapLocalSummary: String {
        guard case .mapLocal(let file) = draft.actions.stub else { return localized("Not set") }
        if let fileName = file.fileName, !fileName.isEmpty { return fileName }
        guard !file.relativePath.isEmpty else { return localized("Not set") }
        return URL(fileURLWithPath: file.relativePath).lastPathComponent
    }

    /// Copies a picked file into the rules directory and points the map-local stub at the copy.
    ///
    /// The file is copied rather than referenced. A document picked outside the app's container is
    /// only readable through a security-scoped URL that this override cannot hold across a
    /// relaunch, and a path to somebody's Files app is not a path an override can rely on
    /// tomorrow; a copy in the rules directory is readable from the interceptor's thread forever,
    /// and is swept like a mock body when no override points at it.
    ///
    /// The `Content-Type` is filled in from the document's extension when the field is still
    /// empty, and left alone when the developer has typed one.
    ///
    /// - Parameter url: The file the system file importer handed back.
    func importMapLocalFile(from url: URL) {
        guard let path = store.storeFile(at: url) else {
            didFailToImportFile = true
            return
        }
        var file: MapLocalFile
        if case .mapLocal(let existing) = draft.actions.stub {
            file = existing
        } else {
            file = MapLocalFile(relativePath: "")
        }
        file.relativePath = path
        file.fileName = url.lastPathComponent
        if file.contentType?.isEmpty ?? true {
            file.contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        }
        draft.actions.stub = .mapLocal(file)
    }

    /// Reports a failure the file importer itself raised, before any bytes were read.
    func reportFileImportFailure() {
        didFailToImportFile = true
    }

    /// The `Content-Type` a map-local stub returns. Emptying it omits the header.
    var contentType: String {
        get {
            guard case .mapLocal(let file) = draft.actions.stub else { return "" }
            return file.contentType ?? ""
        }
        set {
            guard case .mapLocal(var file) = draft.actions.stub else { return }
            file.contentType = newValue.isEmpty ? nil : newValue
            draft.actions.stub = .mapLocal(file)
        }
    }

    // MARK: - Rewrite

    /// Whether this override rewrites headers. Turning it off remembers what was typed.
    var isRewritingHeaders: Bool {
        get { draft.actions.rewriteHeaders != nil }
        set {
            guard newValue != isRewritingHeaders else { return }
            if newValue {
                let rewrite = rememberedRewrite ?? NetworkHeaderRewrite()
                draft.actions.rewriteHeaders = rewrite
                setHeaders = .fields(from: rewrite.set)
                removedHeaders = .fields(from: rewrite.remove)
            } else {
                rememberedRewrite = draft.actions.rewriteHeaders
                draft.actions.rewriteHeaders = nil
            }
        }
    }

    // MARK: - Condition

    /// Whether this override conditions the request. Turning it off remembers what was typed.
    var isConditioning: Bool {
        get { draft.actions.condition != nil }
        set {
            guard newValue != isConditioning else { return }
            if newValue {
                draft.actions.condition = rememberedCondition ?? NetworkCondition()
            } else {
                rememberedCondition = draft.actions.condition
                draft.actions.condition = nil
            }
        }
    }

    /// The seconds the condition adds before the request is sent, or before a stub answers.
    var latency: TimeInterval {
        get { draft.actions.condition?.latency ?? 0 }
        set {
            guard var condition = draft.actions.condition else { return }
            condition.latency = newValue
            draft.actions.condition = condition
        }
    }

    /// The condition's bandwidth ceiling in kilobytes per second. `0` means unthrottled.
    var bandwidthKBps: Int {
        get { draft.actions.condition?.bandwidthKBps ?? 0 }
        set {
            guard var condition = draft.actions.condition else { return }
            condition.bandwidthKBps = newValue > 0 ? newValue : nil
            draft.actions.condition = condition
        }
    }

    /// The fraction of matching requests the condition fails, from `0` to `1`.
    var failureRate: Double {
        get { draft.actions.condition?.failureRate ?? 0 }
        set {
            guard var condition = draft.actions.condition else { return }
            condition.failureRate = newValue
            draft.actions.condition = condition
        }
    }

    // MARK: - Saving

    /// Writes the draft to the store, adding it when new and replacing it in place when not.
    ///
    /// Does nothing for a draft that fails ``isValid``. The view already disables its confirm
    /// button, but the guard belongs here too: the check is the rule, not the button's appearance.
    ///
    /// New body bytes are handed to the store rather than written here, and only when they differ
    /// from what the editor opened with — so re-saving an unchanged rule neither rewrites its body
    /// nor orphans a copy of it. The store writes the bytes, points the rule at them, and reclaims
    /// whatever file the replaced rule owned, unless another override still points at it.
    ///
    /// - Returns: `false` when the rule was not stored, which today means its body could not be
    ///   written. The sheet stays open and ``didFailToSave`` raises an alert, rather than
    ///   dismissing over an override that does not exist.
    @discardableResult
    func save() -> Bool {
        guard isValid else { return false }

        var rule = draft
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if case .mock(var mock) = rule.actions.stub, bodyText != originalBodyText || isOriginalBodyMissing {
            if bodyText.isEmpty {
                mock.bodyID = nil
                mock.pendingBody = nil
            } else {
                mock.pendingBody = Data(bodyText.utf8)
            }
            rule.actions.stub = .mock(mock)
        }

        let stored = isNewRule ? store.add(rule) : store.update(rule)
        didFailToSave = !stored
        return stored
    }

    // MARK: - Header plumbing

    /// Folds ``responseHeaders`` back into the mock stub. A no-op when nothing is mocked, so
    /// editing headers and then changing the stub kind cannot overwrite the new kind's
    /// configuration.
    private func commitMockHeaders() {
        guard case .mock(var mock) = draft.actions.stub else { return }
        mock.headers = responseHeaders.headerDictionary
        draft.actions.stub = .mock(mock)
    }

    /// Folds ``setHeaders`` and ``removedHeaders`` back into the rewrite. A no-op while the
    /// rewrite is switched off.
    private func commitRewrite() {
        guard draft.actions.rewriteHeaders != nil else { return }
        draft.actions.rewriteHeaders = NetworkHeaderRewrite(set: setHeaders.headerDictionary,
                                                            remove: removedHeaders.headerNames)
    }

    /// Repopulates the mock's editable header rows after the stub kind changes.
    private func reloadResponseHeaders() {
        guard case .mock(let mock) = draft.actions.stub else { return }
        responseHeaders = .fields(from: mock.headers)
    }
}

internal extension NetworkRulePattern.Kind {
    /// The localised label shown in the editor's host and path comparison pickers.
    var title: String {
        switch self {
        case .exact: return localized("Exact")
        case .contains: return localized("Contains")
        case .wildcard: return localized("Wildcard")
        }
    }
}

internal extension NetworkRuleMatch {
    /// Whether this match names an endpoint rather than a swathe of the app's traffic.
    ///
    /// A match with no host, path or query applies to every request the app makes — every `GET`
    /// of them, if a method is selected, which is not meaningfully narrower. Those are legal
    /// values, because the engine treats an empty facet as "any", but they are almost never what
    /// a developer typing into the editor intended, so ``NetworkRuleEditorViewModel/isValid``
    /// refuses them.
    ///
    /// Methods deliberately do not count: they narrow *how* a request is made, never *what* it
    /// is made to.
    var hasHostPathOrQuery: Bool {
        if let host, !host.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let path, !path.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !query.isEmpty
    }
}
