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
/// - ``bodyEditability``
/// - ``BodyEditability``
/// - ``maximumEditableBodyBytes``
/// - ``responseHeaders``
/// - ``mapLocalSummary``
/// - ``importMapLocalFile(from:)``
/// - ``didFailToImportFile``
/// - ``didFailToSave``
/// - ``contentType``
/// - ``contentTypes``
/// - ``contentTypeSelection``
/// - ``isCustomContentType``
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
    /// Whether the stored mock body can be edited as text, and why not when it cannot.
    ///
    /// The body used to be loaded with a lossy UTF-8 decode, so opening a captured image as a
    /// mock and touching the field wrote every byte that is not UTF-8 back as a replacement
    /// character — one tap from **Save as mock** on a PNG. A body Scyther cannot represent as text
    /// is shown as a size and left alone instead.
    enum BodyEditability: Equatable {
        /// UTF-8 text small enough to load into the editor.
        case editable
        /// Bytes that are not valid UTF-8, so editing them as text would destroy them.
        case notText
        /// Valid text, but larger than ``NetworkRuleEditorViewModel/maximumEditableBodyBytes``.
        case tooLarge
    }

    /// The largest body loaded into the text editor, in bytes.
    ///
    /// The body is read and decoded on the main actor, by the view's first render. A megabyte of
    /// JSON is already more than anyone edits by hand in a `TextEditor`, and a mock body has no
    /// upper bound at all — a HAR import can carry one the size of a video.
    static let maximumEditableBodyBytes: Int = 1_048_576

    /// The `Content-Type` values the map-local picker offers, in the order it lists them.
    ///
    /// Registered MIME types, deliberately not localised and deliberately shown verbatim: the
    /// string in the list is the string that goes out on the wire, and a developer choosing
    /// between them is choosing a protocol token, not reading prose. Anything not here is typed
    /// into the Custom field — see ``isCustomContentType``.
    static let contentTypes: [String] = [
        "application/json",
        "text/plain",
        "text/html",
        "application/xml",
        "text/csv",
        "text/javascript",
        "image/png",
        "image/jpeg",
        "image/gif",
        "image/svg+xml",
        "application/pdf",
        "application/octet-stream",
    ]

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
    ///
    /// Always `""` while ``bodyEditability`` is anything but ``BodyEditability/editable``: the
    /// bytes are not text, or are too large to load, and the editor does not offer them.
    @Published var bodyText: String {
        didSet {
            guard bodyEditability == .editable else { return }
            bodyByteCount = bodyText.utf8.count
        }
    }

    /// Whether the body can be edited as text, and why not when it cannot.
    private(set) var bodyEditability: BodyEditability

    /// The size ``bodySummary`` reports.
    ///
    /// Held rather than derived, because `bodySummary` is read on every evaluation of the row that
    /// shows it and counting the UTF-8 bytes of the whole body each time is work the view does not
    /// need. For a body that is not editable this is the size of the file on disk, which is the
    /// only honest answer: there is no decoded string whose length would mean anything.
    private var bodyByteCount: Int

    /// Whether the map-local content type is being typed by hand rather than picked.
    ///
    /// Drives the Custom entry in the picker and the text field it reveals. Seeded from the
    /// stored value, so reopening an override typed as `application/vnd.example+json` comes back
    /// on Custom with that string in the field rather than silently snapping to something else.
    @Published var isCustomContentType: Bool

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
    ///
    /// Cleared by a successful ``save()``, which has just repaired it.
    private var isOriginalBodyMissing: Bool

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
    ///
    /// Cleared by the first successful ``save()``: the rule is in the store from then on, so a
    /// second confirm updates it in place rather than upserting it again.
    private var isNewRule: Bool

    /// The body text as it was when the editor was last in step with the store, so ``save()`` can
    /// tell whether the developer actually changed it and avoid writing a second copy of
    /// identical bytes.
    ///
    /// Advanced by a successful ``save()``. The confirm button stays tappable until the sheet has
    /// dismissed, and without this a second tap wrote the same bytes to a second file.
    private var originalBodyText: String

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

        self.rememberedHostKind = draft.match.host?.kind ?? .exact
        self.rememberedPathKind = draft.match.path?.kind ?? .exact

        let loaded = Self.loadBody(of: draft.actions.stub, from: store)
        self.bodyText = loaded.text
        self.originalBodyText = loaded.text
        self.bodyEditability = loaded.editability
        self.bodyByteCount = loaded.byteCount
        self.isOriginalBodyMissing = loaded.isMissing

        if case .mapLocal(let file) = draft.actions.stub, let type = file.contentType, !type.isEmpty {
            self.isCustomContentType = !Self.contentTypes.contains(type)
        } else {
            // No content type yet means None, not Custom — Custom would reveal an empty field for
            // a value the developer has not decided to give.
            self.isCustomContentType = false
        }

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
    /// A facet that matches everything does not count, however it is spelled: a path of `*` set to
    /// Wildcard, or `/` set to Contains, is two taps and one character away from an enabled
    /// override applied to every request in the app.
    var isValid: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !draft.actions.isEmpty else { return false }
        return draft.match.narrowsTraffic
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
                draft.actions.stub = rememberedStubs[.mapLocal] ?? .mapLocal(MapLocalFile(path: ""))
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
    ///
    /// Reports the size of what is stored rather than the length of a decoded string, so a body
    /// the editor refuses to open as text still says how big it is.
    var bodySummary: String {
        bodyByteCount == 0 ? localized("Not set") : localized("\(bodyByteCount) bytes")
    }

    /// What the editor may do with the body a stub already holds.
    ///
    /// Reading and decoding happens once, here, rather than on every evaluation of the row that
    /// shows it — and only for a body small enough to be worth loading onto the main actor at
    /// all, which the file's size settles without reading a byte of it.
    ///
    /// - Parameters:
    ///   - stub: The stub the editor opened on.
    ///   - store: Where a stored body is read from.
    /// - Returns: The text to edit, how editable it is, its size, and whether the identifier the
    ///   stub carries points at bytes that are not there.
    private static func loadBody(
        of stub: NetworkRuleStub?,
        from store: NetworkRuleStore
    ) -> (text: String, editability: BodyEditability, byteCount: Int, isMissing: Bool) {
        guard case .mock(let mock) = stub else { return ("", .editable, 0, false) }

        if let pending = mock.pendingBody {
            guard pending.count <= maximumEditableBodyBytes else {
                return ("", .tooLarge, pending.count, false)
            }
            guard let text = String(data: pending, encoding: .utf8) else {
                return ("", .notText, pending.count, false)
            }
            return (text, .editable, pending.count, false)
        }

        guard let bodyID = mock.bodyID else { return ("", .editable, 0, false) }
        guard let size = store.bodyByteCount(for: bodyID) else { return ("", .editable, 0, true) }
        guard size <= maximumEditableBodyBytes else { return ("", .tooLarge, size, false) }
        guard let data = store.bodyData(for: bodyID) else { return ("", .editable, 0, true) }
        guard let text = String(data: data, encoding: .utf8) else {
            return ("", .notText, data.count, false)
        }
        return (text, .editable, data.count, false)
    }

    /// The name of the file a map-local stub serves, or the invitation to choose one.
    ///
    /// The copy on disk is named after an identifier so it can be swept like a mock body, so the
    /// name of the document it was made from is what the row shows. A path supplied from code
    /// carries no such name, and falls back to the file name on the end of that path.
    ///
    /// One row does the choosing and the reporting — tapping it opens the picker either way — so
    /// while nothing is chosen this reads as the invitation rather than as an absence.
    var mapLocalSummary: String {
        guard case .mapLocal(let file) = draft.actions.stub else { return localized("Choose File") }
        if let fileName = file.fileName, !fileName.isEmpty { return fileName }
        guard !file.path.isEmpty else { return localized("Choose File") }
        return URL(fileURLWithPath: file.path).lastPathComponent
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
            file = MapLocalFile(path: "")
        }
        file.path = path
        file.fileName = url.lastPathComponent
        if file.contentType?.isEmpty ?? true {
            let derived = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            file.contentType = derived
            isCustomContentType = derived.map { !Self.contentTypes.contains($0) } ?? false
        }
        draft.actions.stub = .mapLocal(file)
    }

    /// Reports a failure the file importer itself raised, before any bytes were read.
    func reportFileImportFailure() {
        didFailToImportFile = true
    }

    /// The `Content-Type` a map-local stub returns. Emptying it omits the header.
    ///
    /// Bound to the Custom text field, and written by ``contentTypeSelection`` when a listed type
    /// is picked. Trimmed by ``save()``, like the host and path: a MIME type with a stray space on
    /// the end is a header the server would never have sent, and it fails silently at request time.
    var contentType: String {
        get {
            guard case .mapLocal(let file) = draft.actions.stub else { return "" }
            return file.contentType ?? ""
        }
        set {
            guard case .mapLocal(var file) = draft.actions.stub else { return }
            file.contentType = newValue.isEmpty ? nil : newValue
            // Keep the Custom field on screen for a value the picker cannot represent, whoever
            // wrote it — otherwise typing one would hide the field that is holding it.
            if !newValue.isEmpty, !Self.contentTypes.contains(newValue) {
                isCustomContentType = true
            }
            draft.actions.stub = .mapLocal(file)
        }
    }

    /// Which entry of the content type picker is selected, or `nil` for Custom.
    ///
    /// MIME types are a registered set, and one typed wrong fails silently at request time — the
    /// stub serves the file under a header nothing can parse — so the ordinary path is to pick one
    /// rather than spell it. Custom stays available for the rest, and keeps whatever the entry
    /// already held rather than clearing it, so switching to Custom to adjust a type is not a
    /// retype.
    var contentTypeSelection: ContentTypeChoice {
        get {
            if isCustomContentType { return .custom }
            let type = contentType
            if type.isEmpty { return .unset }
            // A value that is not one of the offered ones is Custom however it got there — a HAR
            // import and a picked file can both produce one without the picker being touched.
            return Self.contentTypes.contains(type) ? .listed(type) : .custom
        }
        set {
            switch newValue {
            case .unset:
                isCustomContentType = false
                contentType = ""
            case .listed(let type):
                isCustomContentType = false
                contentType = type
            case .custom:
                isCustomContentType = true
            }
        }
    }

    /// What the Content type picker is showing.
    ///
    /// Three states rather than two, because "no content type at all" is a real answer and used to
    /// be spelled as Custom with an empty field — which showed a text field for nothing and made
    /// the omission look like an unfinished entry.
    enum ContentTypeChoice: Hashable {
        /// No `Content-Type` header is returned.
        case unset
        /// One of ``NetworkRuleEditorViewModel/contentTypes``.
        case listed(String)
        /// Anything else, typed into the field the picker reveals.
        case custom
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
    /// Every number the form holds is brought into range first — see ``inRange(_:)`` — and the
    /// `Content-Type` is trimmed, like the host and the path.
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

        draft.actions = Self.inRange(draft.actions)
        var rule = draft
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let bodyChanged = bodyEditability == .editable && (bodyText != originalBodyText || isOriginalBodyMissing)
        if case .mock(var mock) = rule.actions.stub, bodyChanged {
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
        guard stored else { return false }

        // The confirm button stays tappable until the sheet has dismissed. Bringing the editor
        // level with the store means a second tap updates the rule in place and writes no second
        // copy of a body that has not changed since the first. The draft is re-read rather than
        // assumed, because the store is what fills in the identifier of the body it just wrote —
        // without that the second save would look like an override whose body had been emptied.
        isNewRule = false
        originalBodyText = bodyText
        isOriginalBodyMissing = false
        if let stored = (store.rules + store.transientRules).first(where: { $0.id == rule.id }) {
            draft = stored
        }
        return true
    }

    /// The same actions with every number brought into the range it is allowed to hold.
    ///
    /// A status code of `-1` or `700`, a negative delay and a delay of `NaN` all used to reach the
    /// store. Nothing crashed — the responder guards the response it builds — but a negative delay
    /// was silently accepted and quietly meant zero, and a status outside `100...599` is not a
    /// status any client will read as one. Clamping here rather than in the field's setter leaves
    /// typing alone: a partly typed `20` must not rewrite itself to `100` between keystrokes.
    ///
    /// - Parameter actions: What the form currently holds.
    /// - Returns: The same actions, storable.
    private static func inRange(_ actions: NetworkRuleActions) -> NetworkRuleActions {
        var actions = actions
        switch actions.stub {
        case .mock(var mock):
            mock.statusCode = statusCodeInRange(mock.statusCode)
            mock.delay = secondsInRange(mock.delay)
            actions.stub = .mock(mock)
        case .mapLocal(var file):
            file.statusCode = statusCodeInRange(file.statusCode)
            file.delay = secondsInRange(file.delay)
            file.contentType = file.contentType?.trimmingCharacters(in: .whitespacesAndNewlines)
            if file.contentType?.isEmpty ?? false { file.contentType = nil }
            actions.stub = .mapLocal(file)
        case nil:
            break
        }
        if var condition = actions.condition {
            condition.latency = secondsInRange(condition.latency)
            condition.failureRate = min(max(condition.failureRate.isNaN ? 0 : condition.failureRate, 0), 1)
            if let bandwidth = condition.bandwidthKBps, bandwidth <= 0 { condition.bandwidthKBps = nil }
            actions.condition = condition
        }
        return actions
    }

    /// A status code brought inside the range HTTP defines.
    ///
    /// - Parameter code: What the field holds.
    /// - Returns: The code, clamped to `100...599`.
    private static func statusCodeInRange(_ code: Int) -> Int {
        min(max(code, 100), 599)
    }

    /// A number of seconds brought inside the range a wait can be.
    ///
    /// - Parameter seconds: What the field holds.
    /// - Returns: The value, or `0` when it is negative or not a number.
    private static func secondsInRange(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return seconds
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

internal extension NetworkRulePattern {
    /// Whether this pattern rules any candidate out.
    ///
    /// A wildcard of nothing but `*` matches every string there is, so it constrains exactly as
    /// much as leaving the field empty — and reads, in the editor, as though it constrains
    /// something. So does a blank value, which the editor collapses to no facet at all anyway.
    var matchesEverything: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        switch kind {
        case .exact, .contains: return false
        case .wildcard: return trimmed.allSatisfy { $0 == "*" }
        }
    }

    /// Whether this pattern rules any request out when it is used as the **path** facet.
    ///
    /// One case on top of ``matchesEverything``: every URL path a request can carry begins with
    /// `/`, so `Contains /` is `Wildcard *` spelled differently. Deliberately not applied to the
    /// host facet, where a slash can never appear and `Contains /` matches nothing rather than
    /// everything — a different mistake, and not one this guard is about.
    var matchesEveryPath: Bool {
        if matchesEverything { return true }
        return kind == .contains && value.trimmingCharacters(in: .whitespacesAndNewlines) == "/"
    }
}

internal extension NetworkRuleMatch {
    /// Whether this match names an endpoint rather than a swathe of the app's traffic.
    ///
    /// A match with no host, path or query applies to every request the app makes — every `GET`
    /// of them, if a method is selected, which is not meaningfully narrower. So does one whose
    /// only facet matches everything anyway. Those are legal values, because the engine treats an
    /// empty facet as "any", but they are almost never what a developer typing into the editor
    /// intended, so ``NetworkRuleEditorViewModel/isValid`` refuses them.
    ///
    /// Methods deliberately do not count: they narrow *how* a request is made, never *what* it
    /// is made to.
    var narrowsTraffic: Bool {
        if let host, !host.matchesEverything { return true }
        if let path, !path.matchesEveryPath { return true }
        return !query.isEmpty
    }
}
