//
//  NetworkRuleStore.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import Combine
import Foundation

/// Owns the rules: their order, their persistence, and the mock bodies they point at.
///
/// The store is the single writer of rule state. Every mutation persists the durable rules to
/// `UserDefaults.scyther` and republishes ``NetworkRuleSnapshot``, so the interceptor — which
/// runs off the main actor and cannot read this class — always sees the current rule set.
///
/// ## Persisted versus transient
///
/// Rules added with ``add(_:)`` survive relaunch. Rules added with ``addTransient(_:)`` never
/// touch `UserDefaults`; they exist for the lifetime of the process only, which is what a host
/// app registering rules from code at launch wants. Persisted rules always take precedence over
/// transient ones, because the developer's explicit choice in the menu should win over a rule the
/// app installed for itself.
///
/// ## Bodies
///
/// A mock response's body is too large to live comfortably in `UserDefaults`, so ``storeBody(_:)``
/// writes the bytes to a file named after a fresh identifier and the rule stores only that
/// identifier. Deleting a rule deletes the file with it, and ``sweepOrphanedBodies()`` reclaims
/// the ones no surviving rule points at. The directory is excluded from the host app's backup.
///
/// ## Topics
///
/// ### Shared Instance
/// - ``shared``
///
/// ### Creating a Store
/// - ``init(defaults:bodyDirectory:)``
/// - ``defaultBodyDirectory``
///
/// ### Reading Rules
/// - ``rules``
/// - ``transientRules``
/// - ``isEnabled``
///
/// ### Mutating Rules
/// - ``add(_:)``
/// - ``add(contentsOf:)``
/// - ``addTransient(_:)``
/// - ``update(_:)``
/// - ``remove(id:)``
/// - ``move(from:to:)``
/// - ``removeAll()``
///
/// ### Mock Bodies
/// - ``storeBody(_:)``
/// - ``bodyURL(for:)``
/// - ``bodyData(for:)``
/// - ``bodyDataOffMainActor(for:)``
/// - ``sweepOrphanedBodies()``
@MainActor
internal final class NetworkRuleStore: ObservableObject {
    /// The `UserDefaults` keys the store writes.
    private enum Key {
        /// The JSON-encoded array of persisted rules.
        static let rules = "Scyther.NetworkRules.Rules"
        /// The master switch. Absent means enabled.
        static let isEnabled = "Scyther.NetworkRules.Enabled"
    }

    /// The store the menu and the public facade both use.
    static let shared = NetworkRuleStore()

    /// The preferences store rules are persisted to.
    private let defaults: UserDefaults

    /// The directory mock response bodies are written to.
    private let bodyDirectory: URL

    /// The persisted rules, in precedence order. Highest precedence first.
    @Published private(set) var rules: [NetworkRule] = []

    /// Rules registered from code for this launch only, evaluated after every persisted rule.
    @Published private(set) var transientRules: [NetworkRule] = []

    /// The master switch. Turning it off leaves every rule intact but stops the interceptor
    /// applying any of them.
    @Published var isEnabled: Bool {
        didSet {
            persistEnabled()
            publish()
        }
    }

    /// Creates a store backed by a preferences store and a body directory.
    ///
    /// Decoding is tolerant: a rule whose JSON this version of Scyther cannot understand — an
    /// action added by a newer release, say — is dropped, and the rules either side of it are
    /// still loaded.
    ///
    /// - Parameters:
    ///   - defaults: Where rules and the master switch are persisted. Defaults to Scyther's own
    ///     suite; tests pass a throwaway suite.
    ///   - bodyDirectory: Where mock response bodies are written. Defaults to
    ///     ``defaultBodyDirectory``.
    init(defaults: UserDefaults = .scyther, bodyDirectory: URL = NetworkRuleStore.defaultBodyDirectory) {
        self.defaults = defaults
        self.bodyDirectory = bodyDirectory
        self.rules = Self.decodeRules(from: defaults.data(forKey: Key.rules))
        self.isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        publish()
    }

    // MARK: - Activation

    /// Publishes the current rules so the interceptor applies them from the first request.
    ///
    /// Loading the persisted rules and publishing them is something only *constructing* the store
    /// does, and nothing outside this folder constructs it. Without a call from
    /// ``Scyther/start()`` an override a developer enabled yesterday would sit dormant after a
    /// relaunch and then switch itself on mid-session, the moment the overrides screen happened
    /// to be opened.
    ///
    /// Idempotent: it republishes state the store already holds, so calling it more than once
    /// costs a snapshot and changes nothing.
    func activate() {
        publish()
    }

    // MARK: - Mutation

    /// Adds a rule that survives relaunch, at the lowest precedence of the persisted rules.
    ///
    /// Adding is an upsert: a rule whose identifier is already stored **replaces** that rule in
    /// place rather than appending a second copy. A host app that registers an override from
    /// `didFinishLaunching` would otherwise grow both the persisted blob and the menu list by one
    /// row on every launch, and two rows sharing an identifier make ``update(_:)`` and
    /// ``remove(id:)`` reach only the first of them.
    ///
    /// Callers who want one stable override across launches should therefore build it with a
    /// stable identifier — see ``NetworkRules/add(_:)``.
    ///
    /// - Parameter rule: The rule to add, or the replacement for a rule already stored under the
    ///   same identifier.
    func add(_ rule: NetworkRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persistRules()
        publish()
    }

    /// Appends several rules that survive relaunch, persisting and publishing once for the lot.
    ///
    /// Every mutation JSON-encodes the whole rules array into `UserDefaults` and republishes the
    /// interceptor's snapshot, so adding a HAR import's worth of rules one at a time costs one
    /// full encode and one snapshot per entry. HAR files routinely hold hundreds of entries.
    ///
    /// - Parameter newRules: The rules to add, in the order they should be evaluated. Adding
    ///   none is a no-op, so an import that produced nothing does not churn the snapshot.
    func add(contentsOf newRules: [NetworkRule]) {
        guard !newRules.isEmpty else { return }
        rules.append(contentsOf: newRules)
        persistRules()
        publish()
    }

    /// Adds a rule for this launch only. It is never written to `UserDefaults`.
    ///
    /// Upserts by identifier exactly as ``add(_:)`` does, so registering the same override twice
    /// in one launch — from a helper called on every sign-in, say — leaves one row rather than a
    /// growing pile of identical ones.
    ///
    /// - Parameter rule: The rule to add, or the replacement for a transient rule already
    ///   registered under the same identifier.
    func addTransient(_ rule: NetworkRule) {
        if let index = transientRules.firstIndex(where: { $0.id == rule.id }) {
            transientRules[index] = rule
        } else {
            transientRules.append(rule)
        }
        publish()
    }

    /// Replaces the stored rule carrying the same identifier, leaving its position alone.
    ///
    /// Does nothing when no rule has that identifier, so an edit of a rule deleted in the
    /// meantime cannot resurrect it.
    ///
    /// - Parameter rule: The edited rule.
    func update(_ rule: NetworkRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            persistRules()
            publish()
        } else if let index = transientRules.firstIndex(where: { $0.id == rule.id }) {
            transientRules[index] = rule
            publish()
        }
    }

    /// Deletes the rule with this identifier, along with any mock body it owns.
    ///
    /// - Parameter id: The identifier of the rule to delete.
    func remove(id: UUID) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            deleteBody(for: rules.remove(at: index))
            persistRules()
            publish()
        } else if let index = transientRules.firstIndex(where: { $0.id == id }) {
            deleteBody(for: transientRules.remove(at: index))
            publish()
        }
    }

    /// Reorders the persisted rules, which is what changes their precedence.
    ///
    /// - Parameters:
    ///   - source: The offsets being moved, as supplied by SwiftUI's `onMove`.
    ///   - destination: The offset to move them to.
    func move(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        persistRules()
        publish()
    }

    /// Deletes every rule, persisted and transient, and every mock body they own.
    func removeAll() {
        for rule in rules + transientRules {
            deleteBody(for: rule)
        }
        rules.removeAll()
        transientRules.removeAll()
        persistRules()
        publish()
    }

    // MARK: - Bodies

    /// The directory mock bodies are written to when none is supplied.
    ///
    /// `Application Support/Scyther/NetworkRules`, which is inside the app's own container and is
    /// not purged the way the caches directory is.
    ///
    /// - Note: Falls back to the temporary directory in the impossible case that the system
    ///   reports no Application Support directory, so that a debugging tool can never crash its
    ///   host over a file path.
    nonisolated static var defaultBodyDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Scyther/NetworkRules", isDirectory: true)
    }

    /// Writes a mock response body to disk and returns the identifier a rule stores instead.
    ///
    /// - Parameter data: The body bytes.
    /// - Returns: The identifier to put in ``MockResponse/bodyID``.
    @discardableResult
    func storeBody(_ data: Data) -> UUID {
        let id = UUID()
        createBodyDirectory()
        try? data.write(to: bodyURL(for: id), options: .atomic)
        return id
    }

    /// Creates the body directory if it is not there, and keeps it out of the host app's backup.
    ///
    /// `Application Support` is backed up to iCloud by default. A colleague's 40 MB HAR import is
    /// a debugging artefact, not the user's data, and inflating someone's backup by the size of
    /// it is not a thing a debugging tool should do.
    private func createBodyDirectory() {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: bodyDirectory.path) else { return }
        try? fileManager.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)

        var directory = bodyDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    /// The file a stored body lives at.
    ///
    /// - Parameter id: The body identifier held by a ``MockResponse``.
    /// - Returns: The file URL, whether or not anything has been written there.
    func bodyURL(for id: UUID) -> URL {
        bodyDirectory.appendingPathComponent(id.uuidString, isDirectory: false)
    }

    /// The bytes of a stored body.
    ///
    /// - Parameter id: The body identifier held by a ``MockResponse``.
    /// - Returns: The body, or `nil` when nothing has been written for that identifier.
    func bodyData(for id: UUID) -> Data? {
        try? Data(contentsOf: bodyURL(for: id))
    }

    /// The bytes of a stored body, read without touching the main actor.
    ///
    /// `HTTPInterceptorURLProtocol` synthesises a mock response on a thread owned by the URL
    /// loading system, where awaiting the main actor risks a deadlock. This reads the same file
    /// ``bodyData(for:)`` reads, from ``defaultBodyDirectory``.
    ///
    /// - Parameter id: The body identifier held by a ``MockResponse``.
    /// - Returns: The body, or `nil` when nothing has been written for that identifier.
    ///
    /// - Note: Reads ``NetworkRuleSnapshot/current``'s body directory — the directory belonging to
    ///   the store that published the rules being applied — rather than assuming
    ///   ``defaultBodyDirectory``. That keeps the `bodyDirectory` injection point honoured off the
    ///   main actor as well as on it, with no separate global to fall out of step or dangle.
    nonisolated static func bodyDataOffMainActor(for id: UUID) -> Data? {
        let url = NetworkRuleSnapshot.current.bodyDirectory
            .appendingPathComponent(id.uuidString, isDirectory: false)
        return try? Data(contentsOf: url)
    }

    /// Deletes body files that no rule points at any more.
    ///
    /// Four call sites write a body — the editor, a HAR import, save-as-mock, and
    /// ``MockResponse/json(_:status:delay:)`` — and only deleting a rule deletes one. A rule
    /// abandoned in the editor, a rule dropped on decode because a newer Scyther wrote it, and
    /// every body a transient rule ever pointed at therefore strand their bytes on disk forever.
    /// This is the sweep that reclaims them, called from ``Scyther/start()`` beside
    /// `NetworkLogCleaner.shared.cleanupOldLogs()`.
    ///
    /// The referenced identifiers are collected here, on the main actor; the file enumeration and
    /// the deletions happen off it, because a directory holding a HAR import's worth of bodies is
    /// not something to walk while a host app is trying to draw its first frame.
    func sweepOrphanedBodies() {
        let referenced = Set((rules + transientRules).compactMap { rule -> UUID? in
            guard case .mock(let mock) = rule.action else { return nil }
            return mock.bodyID
        })
        let directory = bodyDirectory
        Task.detached(priority: .utility) {
            Self.sweepBodies(in: directory, keeping: referenced, ignoringFilesNewerThan: Self.bodySweepGracePeriod)
        }
    }

    /// How recently a body may have been written and still survive a sweep, in seconds.
    ///
    /// A body is written before the rule that points at it is stored — ``MockResponse/json(_:status:delay:)``
    /// writes when the value is *constructed* — so a host app calling `Scyther.start()` and then
    /// registering an override is briefly holding bytes nothing references yet. Without a grace
    /// period the sweep could delete a mock's body seconds before it was first used.
    nonisolated static let bodySweepGracePeriod: TimeInterval = 60

    /// Deletes every file in `directory` whose name is not a referenced identifier.
    ///
    /// Deliberately conservative: a file whose name is not a UUID at all is left alone, because
    /// this walks a directory inside the host app's container and deleting something it did not
    /// write would be far worse than leaving a stray file behind.
    ///
    /// - Parameters:
    ///   - directory: The body directory to sweep.
    ///   - referenced: The identifiers rules still point at.
    ///   - ignoringFilesNewerThan: Files modified more recently than this many seconds ago are
    ///     left alone — see ``bodySweepGracePeriod``.
    nonisolated static func sweepBodies(in directory: URL,
                                        keeping referenced: Set<UUID>,
                                        ignoringFilesNewerThan grace: TimeInterval) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory,
                                                               includingPropertiesForKeys: [.contentModificationDateKey],
                                                               options: .skipsHiddenFiles) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-grace)
        for file in files {
            guard let id = UUID(uuidString: file.lastPathComponent), !referenced.contains(id) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, modified < cutoff else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    /// Deletes the body file a rule owns, if it owns one.
    ///
    /// - Parameter rule: The rule being deleted.
    private func deleteBody(for rule: NetworkRule) {
        guard case .mock(let mock) = rule.action, let bodyID = mock.bodyID else { return }
        try? FileManager.default.removeItem(at: bodyURL(for: bodyID))
    }

    // MARK: - Persistence

    /// Writes the persisted rules to `UserDefaults`. Transient rules are deliberately excluded.
    private func persistRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: Key.rules)
    }

    /// Writes the master switch to `UserDefaults`.
    private func persistEnabled() {
        defaults.set(isEnabled, forKey: Key.isEnabled)
    }

    /// Republishes the interceptor's view of the world after any change.
    ///
    /// Persisted rules come first, so they win a conflict with a transient rule.
    private func publish() {
        NetworkRuleSnapshot.update(isEnabled: isEnabled,
                                   rules: rules + transientRules,
                                   bodyDirectory: bodyDirectory)
    }

    /// Decodes persisted rules, skipping any the current version cannot understand.
    ///
    /// - Parameter data: The JSON written by ``persistRules()``, or `nil` on a first launch.
    /// - Returns: Every rule that decoded cleanly, in stored order.
    private static func decodeRules(from data: Data?) -> [NetworkRule] {
        guard let data else { return [] }
        guard let decoded = try? JSONDecoder().decode([FailableRule].self, from: data) else { return [] }
        return decoded.compactMap(\.rule)
    }
}

/// A ``NetworkRule`` that decodes to `nil` rather than throwing.
///
/// Decoding an array of these and dropping the `nil`s means one unreadable rule — a rule written
/// by a newer Scyther whose action this version has no case for — costs that rule alone, rather
/// than every rule the developer has configured.
private struct FailableRule: Decodable {
    /// The decoded rule, or `nil` when this element could not be understood.
    let rule: NetworkRule?

    /// Attempts to decode a rule, recording failure as `nil`.
    ///
    /// - Parameter decoder: The decoder positioned at one array element.
    init(from decoder: Decoder) throws {
        rule = try? NetworkRule(from: decoder)
    }
}
