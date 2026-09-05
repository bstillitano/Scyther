//
//  NetworkRulesViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Combine
import Foundation

/// Backs ``NetworkRulesView``, the list of configured request overrides.
///
/// The view model is a thin front for ``NetworkRuleStore``: the store stays the single writer of
/// rule state, and this republishes its rules so the list redraws when a rule is added from the
/// editor, from `Scyther.network.rules`, or from a HAR import.
///
/// ## Deletion
///
/// A swipe records the rules in ``pendingDeletions`` rather than deleting them, so the view can
/// put an alert in front of them. Deleting a rule also deletes the mock body it owns, which is
/// not recoverable — worth one tap of confirmation.
///
/// ## Topics
///
/// ### Creating the List
/// - ``init(store:)``
///
/// ### Reading Rules
/// - ``rules``
/// - ``transientRules``
/// - ``isEnabled``
/// - ``subtitle(for:)``
///
/// ### Mutating Rules
/// - ``setEnabled(_:to:)``
/// - ``move(from:to:)``
///
/// ### Confirming a Deletion
/// - ``pendingDeletions``
/// - ``deletionTitle``
/// - ``requestDeletion(at:)``
/// - ``requestDeletion(of:)``
/// - ``confirmDeletion()``
/// - ``cancelDeletion()``
///
/// ### Importing
/// - ``importHAR(from:)``
/// - ``reportImportFailure()``
/// - ``importOutcome``
/// - ``storeFailure``
final class NetworkRulesViewModel: ViewModel {
    /// The persisted rules, in precedence order, mirrored from the store.
    @Published private(set) var rules: [NetworkRule] = []

    /// The rules the host app registered from code for this launch, mirrored from the store.
    ///
    /// The engine evaluates these against live traffic exactly as it does the persisted ones, so
    /// leaving them off the screen would let a developer stare at an empty list while their
    /// requests were being mocked. They are shown read-only: the app owns them, not the menu.
    @Published private(set) var transientRules: [NetworkRule] = []

    /// The rules a swipe has proposed deleting, awaiting confirmation. Empty hides the alert.
    ///
    /// A list rather than one rule because `onDelete` reports an `IndexSet`: in edit mode a
    /// developer can select several rows and delete them in one gesture, and taking only the
    /// first offset would silently keep the rest.
    @Published var pendingDeletions: [NetworkRule] = []

    /// The result of the most recent HAR import, awaiting acknowledgement. `nil` hides the alert.
    @Published var importOutcome: NetworkRuleImportOutcome?

    /// The store this list reads and writes.
    private let store: NetworkRuleStore

    /// Keeps the store's publishers alive for the lifetime of the list.
    private var cancellables: Set<AnyCancellable> = []

    /// Creates the list.
    ///
    /// - Parameter store: The store to mirror. Defaults to the shared store; tests pass their own.
    init(store: NetworkRuleStore = .shared) {
        self.store = store
        super.init()
    }

    override func setup() {
        super.setup()
        // No `receive(on:)`: the store is main-actor isolated and so is this view model, so the
        // values already arrive on the main thread. Hopping would leave the list showing stale
        // rules for a frame after every edit.
        store.$rules
            .sink { [weak self] rules in self?.rules = rules }
            .store(in: &cancellables)
        store.$transientRules
            .sink { [weak self] rules in self?.transientRules = rules }
            .store(in: &cancellables)
        store.$isEnabled
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.$lastFailure
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// The master switch. Turning it off leaves every rule intact but stops the interceptor
    /// applying any of them.
    ///
    /// Reads through to the store rather than mirroring it, so the menu and
    /// `Scyther.network.rules.isEnabled` can never disagree about which is authoritative.
    var isEnabled: Bool {
        get { store.isEnabled }
        set { store.isEnabled = newValue }
    }

    /// The most recent thing the store could not do, awaiting acknowledgement. `nil` hides the
    /// alert.
    ///
    /// Reads through to the store exactly as ``isEnabled`` does, so the alert cannot show a
    /// failure the store has already forgotten. Setting it to `nil` acknowledges the failure.
    var storeFailure: NetworkRuleStoreFailure? {
        get { store.lastFailure }
        set {
            guard newValue == nil else { return }
            store.acknowledgeFailure()
        }
    }

    /// Whether the list has nothing to show.
    ///
    /// Both lists have to be empty: an override registered in code is being applied to live
    /// traffic, so an empty state in front of one would be a lie.
    var isEmpty: Bool { rules.isEmpty && transientRules.isEmpty }

    /// The subtitle for one override's row, naming everything it does.
    ///
    /// An override carries a stub, a rewrite and a condition independently, so the subtitle lists
    /// what is actually switched on rather than naming a single behaviour. It no longer says
    /// whether the override is enabled: the row shows that by reading as disabled, which is
    /// something a developer takes in without reading at all.
    ///
    /// - Parameter rule: The override the row shows.
    /// - Returns: For example `Mock Response · Network Condition`, or `No actions` for an
    ///   override that does nothing — which the editor refuses to save, but which an override
    ///   registered from code may still be.
    func subtitle(for rule: NetworkRule) -> String {
        rule.actions.summary
    }

    /// Enables or disables a single rule.
    ///
    /// - Parameters:
    ///   - rule: The rule to change.
    ///   - isEnabled: Whether the engine should evaluate it.
    func setEnabled(_ rule: NetworkRule, to isEnabled: Bool) {
        var updated = rule
        updated.isEnabled = isEnabled
        store.update(updated)
    }

    /// Reorders the rules, which is what changes their precedence.
    ///
    /// - Parameters:
    ///   - source: The offsets being moved, as supplied by SwiftUI's `onMove`.
    ///   - destination: The offset to move them to.
    func move(from source: IndexSet, to destination: Int) {
        store.move(from: source, to: destination)
    }

    /// Records the swiped rules so the view can confirm before anything is deleted.
    ///
    /// Every offset is kept, not just the first: `onDelete` reports a set, and in edit mode that
    /// set can hold several rows.
    ///
    /// - Parameter offsets: The offsets SwiftUI's `onDelete` reported.
    func requestDeletion(at offsets: IndexSet) {
        pendingDeletions = offsets.sorted().compactMap { rules.indices.contains($0) ? rules[$0] : nil }
    }

    /// Records a rule the row's own delete button named, so the view can confirm first.
    ///
    /// The trailing swipe declares its delete button explicitly — declaring any trailing swipe
    /// action replaces the one `onDelete` would have drawn — so it hands over the rule rather
    /// than an offset.
    ///
    /// - Parameter rule: The override the row offered to delete.
    func requestDeletion(of rule: NetworkRule) {
        pendingDeletions = [rule]
    }

    /// The deletion alert's title, naming the single override or counting the several.
    var deletionTitle: String {
        guard pendingDeletions.count != 1 else {
            return localized("Delete \(pendingDeletions[0].name)?")
        }
        return localized("Delete \(pendingDeletions.count) overrides?")
    }

    /// Deletes every rule recorded by ``requestDeletion(at:)`` and dismisses the alert.
    func confirmDeletion() {
        for rule in pendingDeletions {
            store.remove(id: rule.id)
        }
        pendingDeletions = []
    }

    /// Dismisses the deletion alert, leaving the rules alone.
    func cancelDeletion() {
        pendingDeletions = []
    }

    /// Imports every entry of a HAR document as a disabled mock rule.
    ///
    /// HAR files are routinely multi-megabyte, so the bytes are read off the main actor and the
    /// rules are handed to the store in one batch. Reading on the main actor would freeze the
    /// menu for the length of the read, and adding the rules one at a time would JSON-encode the
    /// whole rules array into `UserDefaults` once per entry.
    ///
    /// - Parameter url: The file the developer picked.
    func importHAR(from url: URL) async {
        guard let data = await Self.contents(of: url) else {
            importOutcome = .failed
            return
        }

        do {
            let imported = try HARRuleImporter.rules(from: data) { store.storeBody($0) }
            store.add(contentsOf: imported)
            importOutcome = .imported(count: imported.count)
        } catch {
            importOutcome = .failed
        }
    }

    /// Reads a picked file's bytes without blocking the main actor.
    ///
    /// The read happens inside a security-scoped access pair, because the URL the system file
    /// importer hands back points outside the app's own container.
    ///
    /// - Parameter url: The file the developer picked.
    /// - Returns: The bytes, or `nil` when the file could not be opened or read.
    private static func contents(of url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }.value
    }

    /// Reports a failure the file importer itself raised, before any bytes were read.
    func reportImportFailure() {
        importOutcome = .failed
    }
}

/// The outcome of a HAR import, as the list's alert presents it.
enum NetworkRuleImportOutcome: Identifiable, Equatable {
    /// The document was read and produced this many overrides, every one of them disabled.
    case imported(count: Int)

    /// The file could not be read, or was not a HAR document.
    case failed

    /// A stable identity, so the alert redraws when one outcome replaces another.
    var id: String {
        switch self {
        case .imported(let count): return "imported.\(count)"
        case .failed: return "failed"
        }
    }

    /// The alert's title.
    var title: String {
        switch self {
        case .imported: return localized("Import Complete")
        case .failed: return localized("Import Failed")
        }
    }

    /// The alert's body copy.
    var message: String {
        switch self {
        case .imported(let count):
            return localized("Imported \(count) overrides. Every imported override starts disabled.")
        case .failed:
            return localized("The selected file could not be read as a HAR document.")
        }
    }
}
