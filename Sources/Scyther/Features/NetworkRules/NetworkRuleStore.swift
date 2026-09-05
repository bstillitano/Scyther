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
/// identifier. Deleting a rule deletes the file with it.
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
/// - ``activeBodyDirectory``
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
        Self.setActiveBodyDirectory(bodyDirectory)
        self.rules = Self.decodeRules(from: defaults.data(forKey: Key.rules))
        self.isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        publish()
    }

    // MARK: - Mutation

    /// Appends a rule that survives relaunch, at the lowest precedence of the persisted rules.
    ///
    /// - Parameter rule: The rule to add.
    func add(_ rule: NetworkRule) {
        rules.append(rule)
        persistRules()
        publish()
    }

    /// Appends a rule for this launch only. It is never written to `UserDefaults`.
    ///
    /// - Parameter rule: The rule to add.
    func addTransient(_ rule: NetworkRule) {
        transientRules.append(rule)
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
        try? FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        try? data.write(to: bodyURL(for: id), options: .atomic)
        return id
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
    /// - Note: Reads ``activeBodyDirectory``, which every store points at itself on creation. In
    ///   an app that is ``defaultBodyDirectory``; a test constructing a store over a throwaway
    ///   directory redirects this too, so a stub served by the interceptor finds the same bytes
    ///   ``bodyData(for:)`` would return.
    nonisolated static func bodyDataOffMainActor(for id: UUID) -> Data? {
        let url = activeBodyDirectory.appendingPathComponent(id.uuidString, isDirectory: false)
        return try? Data(contentsOf: url)
    }

    /// Guards ``storedActiveBodyDirectory`` so the interceptor's threads never observe a
    /// half-written value.
    nonisolated private static let activeBodyDirectoryLock = NSLock()

    /// Backing storage for ``activeBodyDirectory``.
    ///
    /// - Note: Declared `nonisolated(unsafe)` because every access goes through
    ///   ``activeBodyDirectoryLock``, which provides the synchronisation the compiler cannot prove.
    nonisolated(unsafe) private static var storedActiveBodyDirectory: URL = NetworkRuleStore.defaultBodyDirectory

    /// The directory ``bodyDataOffMainActor(for:)`` reads mock bodies from.
    ///
    /// The most recently created store wins. An app creates exactly one — ``shared`` — so this is
    /// ``defaultBodyDirectory`` in practice; the indirection exists so that the `bodyDirectory`
    /// injection point is honoured off the main actor as well as on it.
    nonisolated static var activeBodyDirectory: URL {
        activeBodyDirectoryLock.withLock { storedActiveBodyDirectory }
    }

    /// Points ``bodyDataOffMainActor(for:)`` at a store's body directory.
    ///
    /// - Parameter directory: The directory the newly created store writes bodies to.
    nonisolated private static func setActiveBodyDirectory(_ directory: URL) {
        activeBodyDirectoryLock.withLock { storedActiveBodyDirectory = directory }
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
        NetworkRuleSnapshot.update(isEnabled: isEnabled, rules: rules + transientRules)
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
