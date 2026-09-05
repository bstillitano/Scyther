//
//  BreakpointEditorViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

import Foundation

/// Backs ``BreakpointEditorView``, the form that creates or edits a breakpoint.
///
/// The view model owns a ``draft`` copy and writes nothing until ``save()`` is called, so
/// abandoning the sheet leaves the store untouched.
///
/// ## Validity
///
/// ``isValid`` guards the two mistakes that are easy to make here: an unnamed breakpoint, which is
/// indistinguishable from every other unnamed one while a request is held, and a match that names
/// no endpoint at all — which would hold *every* request the app makes, one after another, for the
/// timeout each. That second one is the reason the guard exists at all; an override with the same
/// mistake merely mocks too much, while a breakpoint with it stops the app dead.
///
/// ## Topics
///
/// ### Creating an Editor
/// - ``init(breakpoint:store:)``
///
/// ### The Breakpoint Being Edited
/// - ``draft``
/// - ``title``
/// - ``isValid``
/// - ``save()``
///
/// ### Match Fields
/// - ``availableMethods``
/// - ``patternKinds``
/// - ``isSelected(method:)``
/// - ``toggle(method:)``
/// - ``methodsSummary``
/// - ``hostText``
/// - ``hostKind``
/// - ``pathText``
/// - ``pathKind``
///
/// ### Timeout
/// - ``timeout``
/// - ``timeoutText``
final class BreakpointEditorViewModel: ViewModel {
    /// The methods the checklist offers, in the order it lists them.
    ///
    /// The same seven the override editor offers, so the two forms do not disagree about what a
    /// method picker looks like.
    static let availableMethods: [String] = NetworkRuleEditorViewModel.availableMethods

    /// The pattern comparisons offered for the host and path fields.
    static let patternKinds: [NetworkRulePattern.Kind] = NetworkRuleEditorViewModel.patternKinds

    /// The breakpoint being edited. Nothing reaches the store until ``save()`` is called.
    @Published var draft: NetworkBreakpoint

    /// Whether this editor is creating a breakpoint rather than editing one.
    private let isCreating: Bool

    /// Where the breakpoint is written on save.
    private let store: BreakpointStore

    /// The comparison to restore when ``hostText`` is typed into after being emptied.
    private var rememberedHostKind: NetworkRulePattern.Kind = .exact

    /// The comparison to restore when ``pathText`` is typed into after being emptied.
    private var rememberedPathKind: NetworkRulePattern.Kind = .exact

    /// Creates the editor.
    ///
    /// - Parameters:
    ///   - breakpoint: The breakpoint to edit, or `nil` to create one.
    ///   - store: Where the breakpoint is written on save. Defaults to the shared store.
    init(breakpoint: NetworkBreakpoint?, store: BreakpointStore = .shared) {
        self.store = store
        self.isCreating = breakpoint == nil
        self.draft = breakpoint ?? NetworkBreakpoint(name: "", match: NetworkRuleMatch())
        if let host = breakpoint?.match.host { rememberedHostKind = host.kind }
        if let path = breakpoint?.match.path { rememberedPathKind = path.kind }
        super.init()
    }

    /// The screen's title: creating or editing.
    var title: String {
        isCreating ? localized("New Breakpoint") : localized("Edit Breakpoint")
    }

    /// Whether the draft can be saved.
    var isValid: Bool {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return draft.match.narrowsTraffic
    }

    /// Writes the draft to the store.
    ///
    /// - Returns: `true` once the breakpoint is stored. Always `true` today; it returns a value so
    ///   the view's confirm button reads the same way the override editor's does, where saving can
    ///   fail.
    @discardableResult
    func save() -> Bool {
        var breakpoint = draft
        breakpoint.name = breakpoint.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCreating {
            store.add(breakpoint)
        } else {
            store.update(breakpoint)
        }
        return true
    }

    // MARK: - Match fields

    /// Whether `method` is part of the match.
    ///
    /// - Parameter method: An uppercased HTTP method.
    /// - Returns: Whether it is selected.
    func isSelected(method: String) -> Bool {
        draft.match.methods.contains(method)
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

    /// The value shown on the row that opens the method checklist.
    ///
    /// Selected methods are listed in ``availableMethods`` order rather than the set's own order,
    /// so the summary reads the same way twice running.
    var methodsSummary: String {
        let known = Self.availableMethods.filter { draft.match.methods.contains($0) }
        let unknown = draft.match.methods.subtracting(Self.availableMethods).sorted()
        let selected = known + unknown
        return selected.isEmpty ? localized("Any method") : selected.joined(separator: ", ")
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

    /// Builds a pattern, collapsing an empty value to `nil` so a blank field places no constraint.
    ///
    /// - Parameters:
    ///   - value: The pattern text.
    ///   - kind: The comparison to use.
    /// - Returns: The pattern, or `nil` when the value is blank.
    private static func pattern(value: String, kind: NetworkRulePattern.Kind) -> NetworkRulePattern? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : NetworkRulePattern(kind: kind, value: trimmed)
    }

    // MARK: - Timeout

    /// The timeout, in seconds, as the stepper reads and writes it.
    ///
    /// Clamped on the way in as well as on the way out, so the value the form shows is always one
    /// the store would accept.
    var timeout: Double {
        get { draft.timeout }
        set { draft.timeout = NetworkBreakpoint.clampedTimeout(newValue) }
    }

    /// The timeout as the stepper's label shows it.
    var timeoutText: String {
        NetworkBreakpoint.secondsText(draft.timeout)
    }

    /// How much the stepper changes the timeout by, in seconds.
    static let timeoutStep: Double = 5
}
