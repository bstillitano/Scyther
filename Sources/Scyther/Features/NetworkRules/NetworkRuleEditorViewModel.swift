//
//  NetworkRuleEditorViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Foundation

/// Backs ``NetworkRuleEditorView``, the form used to create a request override or edit an
/// existing one.
///
/// The view model owns a ``draft`` copy of the rule and writes nothing until ``save()`` is called,
/// so abandoning the sheet leaves the store untouched. Everything the form binds to is exposed
/// here rather than reaching into ``draft`` from the view, which keeps the validation and the
/// action-switching logic in a place a test can reach.
///
/// ## Validity
///
/// ``isValid`` guards two mistakes that are easy to make and unpleasant to debug: an unnamed rule
/// (indistinguishable from every other unnamed rule in the list) and a rule with no match facets
/// at all, which would silently apply to every request the app makes.
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
/// ### Action Fields
/// - ``actionKind``
/// - ``statusCode``
/// - ``delay``
/// - ``bodyText``
/// - ``bodySummary``
/// - ``responseHeaders``
/// - ``filePath``
/// - ``contentType``
/// - ``setHeaders``
/// - ``removedHeaders``
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

    /// The headers a rewrite action sets, as ordered editable rows.
    @Published var setHeaders: [NetworkRuleHeaderField] {
        didSet { commitRewrite() }
    }

    /// The header names a rewrite action removes, as ordered editable rows.
    @Published var removedHeaders: [NetworkRuleHeaderField] {
        didSet { commitRewrite() }
    }

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
    /// identifier every time, and switching the action away from a mock orphans it entirely, so
    /// without this the directory accumulates bodies no rule can ever reach.
    private let originalBodyID: UUID?

    /// The last configuration seen for each action kind.
    ///
    /// Switching the action picker away from a kind and back again would otherwise discard
    /// everything typed into it, which is infuriating when comparing two ways of stubbing the
    /// same endpoint.
    private var rememberedActions: [NetworkRuleActionKind: NetworkRuleAction] = [:]

    /// Creates an editor for a new or existing rule.
    ///
    /// A new rule starts matching `GET`, which gives it one facet and so makes it valid the
    /// moment it is named. Starting with no facets at all would make a freshly named rule fail
    /// validation for a reason the form does not visibly explain.
    ///
    /// - Parameters:
    ///   - rule: The rule to edit, or `nil` to create one.
    ///   - store: Where the rule is written on ``save()``. Defaults to the shared store.
    init(rule: NetworkRule?, store: NetworkRuleStore = .shared) {
        self.store = store
        self.isNewRule = rule == nil

        let draft = rule ?? NetworkRule(
            name: "",
            isEnabled: true,
            match: NetworkRuleMatch(methods: ["GET"]),
            action: .mock(MockResponse())
        )
        self.draft = draft
        self.rememberedActions = [draft.action.kind: draft.action]

        if case .mock(let mock) = draft.action {
            self.originalBodyID = mock.bodyID
        } else {
            self.originalBodyID = nil
        }

        let body: String
        if let originalBodyID, let data = store.bodyData(for: originalBodyID) {
            body = String(decoding: data, as: UTF8.self)
        } else {
            body = ""
        }
        self.bodyText = body
        self.originalBodyText = body

        if case .mock(let mock) = draft.action {
            self.responseHeaders = .fields(from: mock.headers)
        } else {
            self.responseHeaders = []
        }
        if case .rewriteHeaders(let rewrite) = draft.action {
            self.setHeaders = .fields(from: rewrite.set)
            self.removedHeaders = .fields(from: rewrite.remove)
        } else {
            self.setHeaders = []
            self.removedHeaders = []
        }

        super.init()
    }

    // MARK: - Presentation

    /// The editor's navigation title.
    var title: String {
        isNewRule ? localized("New Override") : localized("Edit Override")
    }

    /// Whether ``save()`` should be offered.
    ///
    /// A rule needs a name so it can be told apart in the list, and at least one match facet:
    /// methods, host, path or query. A rule with none of those matches every request the app
    /// makes, which is almost never what the developer meant and is hard to diagnose once
    /// enabled.
    var isValid: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return draft.match.hasAnyFacet
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

    // MARK: - Action

    /// Which behaviour the rule performs. Changing it restores whatever was last typed into the
    /// new kind, rather than resetting it.
    var actionKind: NetworkRuleActionKind {
        get { draft.action.kind }
        set {
            guard newValue != draft.action.kind else { return }
            rememberedActions[draft.action.kind] = draft.action
            draft.action = rememberedActions[newValue] ?? newValue.emptyAction()
            reloadHeaderFields()
        }
    }

    /// The status code a mock or map-local action returns.
    var statusCode: Int {
        get {
            switch draft.action {
            case .mock(let mock): return mock.statusCode
            case .mapLocal(let file): return file.statusCode
            case .rewriteHeaders, .condition: return 200
            }
        }
        set {
            switch draft.action {
            case .mock(var mock): mock.statusCode = newValue; draft.action = .mock(mock)
            case .mapLocal(var file): file.statusCode = newValue; draft.action = .mapLocal(file)
            case .rewriteHeaders, .condition: break
            }
        }
    }

    /// The seconds a mock or map-local action waits before responding.
    var delay: TimeInterval {
        get {
            switch draft.action {
            case .mock(let mock): return mock.delay
            case .mapLocal(let file): return file.delay
            case .rewriteHeaders, .condition: return 0
            }
        }
        set {
            switch draft.action {
            case .mock(var mock): mock.delay = newValue; draft.action = .mock(mock)
            case .mapLocal(var file): file.delay = newValue; draft.action = .mapLocal(file)
            case .rewriteHeaders, .condition: break
            }
        }
    }

    /// A one-line description of the mock body, shown on the row that opens the body editor.
    var bodySummary: String {
        bodyText.isEmpty ? localized("Not set") : localized("\(bodyText.utf8.count) bytes")
    }

    /// The absolute path a map-local action serves.
    var filePath: String {
        get {
            guard case .mapLocal(let file) = draft.action else { return "" }
            return file.relativePath
        }
        set {
            guard case .mapLocal(var file) = draft.action else { return }
            file.relativePath = newValue
            draft.action = .mapLocal(file)
        }
    }

    /// The `Content-Type` a map-local action returns. Emptying it omits the header.
    var contentType: String {
        get {
            guard case .mapLocal(let file) = draft.action else { return "" }
            return file.contentType ?? ""
        }
        set {
            guard case .mapLocal(var file) = draft.action else { return }
            file.contentType = newValue.isEmpty ? nil : newValue
            draft.action = .mapLocal(file)
        }
    }

    /// The seconds a condition adds before the request is sent.
    var latency: TimeInterval {
        get {
            guard case .condition(let condition) = draft.action else { return 0 }
            return condition.latency
        }
        set {
            guard case .condition(var condition) = draft.action else { return }
            condition.latency = newValue
            draft.action = .condition(condition)
        }
    }

    /// A condition's bandwidth ceiling in kilobytes per second. `0` means unthrottled.
    var bandwidthKBps: Int {
        get {
            guard case .condition(let condition) = draft.action else { return 0 }
            return condition.bandwidthKBps ?? 0
        }
        set {
            guard case .condition(var condition) = draft.action else { return }
            condition.bandwidthKBps = newValue > 0 ? newValue : nil
            draft.action = .condition(condition)
        }
    }

    /// The fraction of matching requests a condition fails, from `0` to `1`.
    var failureRate: Double {
        get {
            guard case .condition(let condition) = draft.action else { return 0 }
            return condition.failureRate
        }
        set {
            guard case .condition(var condition) = draft.action else { return }
            condition.failureRate = newValue
            draft.action = .condition(condition)
        }
    }

    // MARK: - Saving

    /// Writes the draft to the store, adding it when new and replacing it in place when not.
    ///
    /// Does nothing for a draft that fails ``isValid``. The view already disables its Save button,
    /// but the guard belongs here too: the check is the rule, not the button's appearance.
    ///
    /// The body is written to disk only when it differs from what the editor opened with, so
    /// re-saving an unchanged rule does not leave an orphaned copy of its body behind. Whatever
    /// body the rule no longer points at is deleted, whether it was superseded by new bytes or
    /// stranded by the action changing to something that is not a mock.
    func save() {
        guard isValid else { return }

        var rule = draft
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if case .mock(var mock) = rule.action {
            if bodyText != originalBodyText {
                let replacement = bodyText.isEmpty ? nil : store.storeBody(Data(bodyText.utf8))
                mock.bodyID = replacement
                rule.action = .mock(mock)
                discardOriginalBody(unless: replacement)
            }
        } else {
            discardOriginalBody(unless: nil)
        }

        if isNewRule {
            store.add(rule)
        } else {
            store.update(rule)
        }
    }

    /// Deletes the body file the editor opened with, unless the saved rule still points at it.
    ///
    /// - Parameter retained: The body identifier the saved rule keeps, if any.
    private func discardOriginalBody(unless retained: UUID?) {
        guard let originalBodyID, originalBodyID != retained else { return }
        try? FileManager.default.removeItem(at: store.bodyURL(for: originalBodyID))
    }

    // MARK: - Header plumbing

    /// Folds ``responseHeaders`` back into the mock action. A no-op for every other action kind,
    /// so editing headers and then switching kind cannot overwrite the new kind's configuration.
    private func commitMockHeaders() {
        guard case .mock(var mock) = draft.action else { return }
        mock.headers = responseHeaders.headerDictionary
        draft.action = .mock(mock)
    }

    /// Folds ``setHeaders`` and ``removedHeaders`` back into the rewrite action.
    private func commitRewrite() {
        guard case .rewriteHeaders = draft.action else { return }
        draft.action = .rewriteHeaders(
            NetworkHeaderRewrite(set: setHeaders.headerDictionary, remove: removedHeaders.headerNames)
        )
    }

    /// Repopulates the editable header rows after the action kind changes.
    private func reloadHeaderFields() {
        switch draft.action {
        case .mock(let mock):
            responseHeaders = .fields(from: mock.headers)
        case .rewriteHeaders(let rewrite):
            setHeaders = .fields(from: rewrite.set)
            removedHeaders = .fields(from: rewrite.remove)
        case .mapLocal, .condition:
            break
        }
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
    /// Whether this match constrains anything at all.
    ///
    /// A match with no facets is a wildcard over every request the app makes. That is a legal
    /// value — the engine treats an empty facet as "any" — but it is almost never what a
    /// developer typing into the editor intended, so ``NetworkRuleEditorViewModel/isValid``
    /// refuses it.
    var hasAnyFacet: Bool {
        if !methods.isEmpty { return true }
        if let host, !host.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let path, !path.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !query.isEmpty
    }
}
