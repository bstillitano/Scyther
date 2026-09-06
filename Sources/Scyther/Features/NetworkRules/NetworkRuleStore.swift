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
/// ### Reporting Failures
/// - ``lastFailure``
/// - ``acknowledgeFailure()``
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
/// ### Stored Files
/// - ``storeBody(_:)``
/// - ``stagingURL(for:in:)``
/// - ``deleteOrphans(_:)``
/// - ``orphanCandidates(in:ignoringFilesNewerThan:)``
/// - ``storeFile(at:)``
/// - ``bodyURL(for:)``
/// - ``bodyData(for:)``
/// - ``bodyByteCount(for:)``
/// - ``bodyDataOffMainActor(for:)``
/// - ``sweepOrphanedBodies()``
/// - ``isSweepSuspended``
/// - ``maximumQuarantinedBlobs``
@MainActor
internal final class NetworkRuleStore: ObservableObject {
    /// The `UserDefaults` keys the store writes.
    private enum Key {
        /// The JSON-encoded array of persisted rules.
        static let rules = "Scyther.NetworkRules.Rules"
        /// Every rules blob this version could not read, moved here rather than overwritten.
        ///
        /// An array rather than one blob: a second unreadable configuration used to overwrite the
        /// first, so a developer who downgraded twice was told twice that their overrides had been
        /// set aside and had one of them thrown away in between.
        static let unreadableRules = "Scyther.NetworkRules.Rules.Unreadable"
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

    /// The most recent thing the store could not do, or `nil` when nothing has gone wrong.
    ///
    /// ``NetworkRulesView`` presents it as an alert and then calls ``acknowledgeFailure()``. It
    /// exists because the two things that can fail here — encoding the rules and decoding them —
    /// both used to fail silently, leaving the developer looking at a list that did not match
    /// what the interceptor was applying.
    @Published private(set) var lastFailure: NetworkRuleStoreFailure?

    /// A persisted blob this version could not decode, held until something is about to overwrite
    /// it.
    ///
    /// `nil` in the ordinary case. While it is set the store knows it does not know what the
    /// developer had configured, which is why ``sweepOrphanedBodies()`` stands down.
    private var unreadableBlob: Data?

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
    /// A blob that will not decode as an array *at all* — truncated, or a future version that
    /// wraps the rules in an object — is a different matter, because there is no element to skip.
    /// The store starts empty, records ``NetworkRuleStoreFailure/rulesNotLoaded``, and keeps the
    /// bytes; the next write appends them to a key of their own rather than overwriting them, so
    /// an unreadable configuration is set aside instead of destroyed.
    ///
    /// Setting a configuration aside sets its bodies aside too. The rules in it name files on disk
    /// this version cannot read the names of, so ``sweepOrphanedBodies()`` stands down for as long
    /// as anything is quarantined rather than only for the launch that quarantined it — see
    /// ``isSweepSuspended``. ``removeAll()`` is the way out: throwing every override away is the
    /// developer saying the set-aside configuration is not wanted either.
    ///
    /// - Parameters:
    ///   - defaults: Where rules and the master switch are persisted. Defaults to Scyther's own
    ///     suite; tests pass a throwaway suite.
    ///   - bodyDirectory: Where mock response bodies are written. Defaults to
    ///     ``defaultBodyDirectory``.
    init(defaults: UserDefaults = .scyther, bodyDirectory: URL = NetworkRuleStore.defaultBodyDirectory) {
        self.defaults = defaults
        self.bodyDirectory = bodyDirectory
        let stored = defaults.data(forKey: Key.rules)
        switch Self.decodeRules(from: stored) {
        case .loaded(let loaded):
            self.rules = loaded
        case .unreadable:
            self.rules = []
            self.unreadableBlob = stored
            self.lastFailure = .rulesNotLoaded
        }
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
    /// Adding is an upsert: a rule whose identifier is already registered **replaces** that rule
    /// rather than appending a second copy. A host app that registers an override from
    /// `didFinishLaunching` would otherwise grow both the persisted blob and the menu list by one
    /// row on every launch, and two rows sharing an identifier make ``update(_:)`` and
    /// ``remove(id:)`` reach only the first of them.
    ///
    /// The upsert reaches across both lists: an identifier lives in exactly one of them, so adding
    /// a rule whose identifier is currently registered as transient *moves* it to the persisted
    /// list. See ``addTransient(_:)`` for the other direction and the reasoning.
    ///
    /// Whatever file the replaced rule owned is reclaimed, unless another surviving rule points at
    /// it too.
    ///
    /// Callers who want one stable override across launches should build it with a stable
    /// identifier — see ``NetworkRules/add(_:)``.
    ///
    /// - Parameter rule: The rule to add, or the replacement for a rule already registered under
    ///   the same identifier.
    /// - Returns: `false` when the rule carried mock body bytes that could not be written, in
    ///   which case **nothing** is stored — a stub pointing at bytes that are not on disk answers
    ///   with the right status and an empty body, which surfaces inside the host app as a decode
    ///   error with nothing pointing back at Scyther. `true` otherwise.
    @discardableResult
    func add(_ rule: NetworkRule) -> Bool {
        guard let rule = prepared(rule) else { return false }
        var updated = rules
        var displaced: [UUID?] = []
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            displaced.append(updated[index].storedFileID)
            updated[index] = rule
        } else {
            updated.append(rule)
            if let index = transientRules.firstIndex(where: { $0.id == rule.id }) {
                var remaining = transientRules
                displaced.append(remaining.remove(at: index).storedFileID)
                transientRules = remaining
            }
        }
        rules = updated
        reclaim(displaced)
        persistRules()
        publish()
        return true
    }

    /// Adds several rules that survive relaunch, persisting and publishing once for the lot.
    ///
    /// Every mutation JSON-encodes the whole rules array into `UserDefaults` and republishes the
    /// interceptor's snapshot, so adding a HAR import's worth of rules one at a time costs one
    /// full encode and one snapshot per entry. HAR files routinely hold hundreds of entries.
    ///
    /// Each rule is upserted exactly as ``add(_:)`` upserts one, so an import that repeats an
    /// identifier leaves one row rather than two, and the replaced row's body is reclaimed.
    ///
    /// - Parameter newRules: The rules to add, in the order they should be evaluated. Adding none
    ///   is a no-op, so an import that produced nothing does not churn the snapshot.
    /// The rules array is rebuilt in a local and assigned once, because `@Published` emits on
    /// every mutation: appending in place would cost the list a rebuild, and the snapshot an
    /// encode, per entry — which is the very thing this method exists to avoid.
    ///
    /// - Returns: How many were stored. A rule whose mock body could not be written is skipped
    ///   rather than stored pointing at bytes that are not there, so this can be fewer than were
    ///   offered.
    @discardableResult
    func add(contentsOf newRules: [NetworkRule]) -> Int {
        guard !newRules.isEmpty else { return 0 }
        var updated = rules
        var remainingTransient = transientRules
        var displaced: [UUID?] = []
        var stored = 0
        for candidate in newRules {
            guard let rule = prepared(candidate) else { continue }
            if let index = updated.firstIndex(where: { $0.id == rule.id }) {
                displaced.append(updated[index].storedFileID)
                updated[index] = rule
            } else {
                updated.append(rule)
                if let index = remainingTransient.firstIndex(where: { $0.id == rule.id }) {
                    displaced.append(remainingTransient.remove(at: index).storedFileID)
                }
            }
            stored += 1
        }
        guard stored > 0 else { return 0 }
        rules = updated
        if remainingTransient.count != transientRules.count {
            transientRules = remainingTransient
        }
        reclaim(displaced)
        persistRules()
        publish()
        return stored
    }

    /// Adds a rule for this launch only. It is never written to `UserDefaults`.
    ///
    /// Upserts by identifier exactly as ``add(_:)`` does, so registering the same override twice
    /// in one launch — from a helper called on every sign-in, say — leaves one row rather than a
    /// growing pile of identical ones.
    ///
    /// An identifier lives in exactly one list. Registering a transient rule under an identifier
    /// the persisted list holds *moves* it: the persisted copy is deleted, along with any file it
    /// owned. Letting the two lists both hold one identifier would mean ``remove(id:)`` deleted
    /// the persisted copy and its body while the transient copy carried on matching and serving an
    /// empty one, so the last registration wins outright rather than half-winning.
    ///
    /// - Parameter rule: The rule to add, or the replacement for a rule already registered under
    ///   the same identifier.
    /// - Returns: `false` when the rule carried mock body bytes that could not be written, in
    ///   which case nothing is stored. `true` otherwise.
    @discardableResult
    func addTransient(_ rule: NetworkRule) -> Bool {
        guard let rule = prepared(rule) else { return false }
        var updated = transientRules
        var displaced: [UUID?] = []
        var didChangePersistedRules = false
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            displaced.append(updated[index].storedFileID)
            updated[index] = rule
        } else {
            updated.append(rule)
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                var remaining = rules
                displaced.append(remaining.remove(at: index).storedFileID)
                rules = remaining
                didChangePersistedRules = true
            }
        }
        transientRules = updated
        reclaim(displaced)
        if didChangePersistedRules { persistRules() }
        publish()
        return true
    }

    /// Replaces the stored rule carrying the same identifier, leaving its position alone.
    ///
    /// Does nothing when no rule has that identifier, so an edit of a rule deleted in the meantime
    /// cannot resurrect it. Whatever file the replaced rule owned is reclaimed, unless another
    /// surviving rule points at it too.
    ///
    /// - Parameter rule: The edited rule.
    /// - Returns: `false` when the rule carried mock body bytes that could not be written, in
    ///   which case nothing is changed. `true` otherwise, including when no rule carries this
    ///   identifier and there is nothing to update — the caller asked for a state that now holds.
    @discardableResult
    func update(_ rule: NetworkRule) -> Bool {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            guard let rule = prepared(rule) else { return false }
            let replaced = rules[index].storedFileID
            rules[index] = rule
            reclaim([replaced])
            persistRules()
            publish()
            return true
        }
        if let index = transientRules.firstIndex(where: { $0.id == rule.id }) {
            guard let rule = prepared(rule) else { return false }
            let replaced = transientRules[index].storedFileID
            transientRules[index] = rule
            reclaim([replaced])
            publish()
            return true
        }
        return true
    }

    /// Deletes the rule with this identifier, along with any file it owns.
    ///
    /// The file survives if another rule points at it: the public API encourages building one
    /// ``MockResponse`` and reusing it, which shares one body identifier between overrides, and
    /// deleting the first of them must not empty the second.
    ///
    /// - Parameter id: The identifier of the rule to delete.
    func remove(id: UUID) {
        guard let removed = takeRule(id: id) else { return }
        reclaim([removed.fileID])
        if removed.wasPersisted { persistRules() }
        publish()
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

    /// Deletes every rule, persisted and transient, and every file they own.
    ///
    /// Also discards anything held in quarantine — a configuration an earlier launch could not
    /// read and set aside — because "delete every override" cannot sensibly mean "except the ones
    /// nobody was ever shown". It is the only thing that discards a quarantine, and doing so is
    /// what lets ``sweepOrphanedBodies()`` start reclaiming again: while a configuration is set
    /// aside the sweep cannot tell which files on disk belong to it, so it stands down entirely.
    func removeAll() {
        let owned: [UUID?] = (rules + transientRules).map(\.storedFileID)
        rules.removeAll()
        transientRules.removeAll()
        unreadableBlob = nil
        defaults.removeObject(forKey: Key.unreadableRules)
        reclaim(owned)
        persistRules()
        publish()
    }

    /// Sanitises a rule and writes any bytes it is still carrying.
    ///
    /// - Parameter rule: The rule about to be stored.
    /// - Returns: The rule as it should be stored, or `nil` when its mock body could not be
    ///   written — in which case ``lastFailure`` says so and the caller stores nothing.
    private func prepared(_ rule: NetworkRule) -> NetworkRule? {
        let rule = rule.sanitised
        guard case .mock(var mock) = rule.actions.stub, let pending = mock.pendingBody else {
            return rule
        }
        do {
            mock.bodyID = try storeBody(pending)
            mock.pendingBody = nil
            var resolved = rule
            resolved.actions.stub = .mock(mock)
            return resolved
        } catch {
            lastFailure = .bodyNotWritten
            return nil
        }
    }

    /// Removes whichever list holds this identifier, since only one of them ever does.
    ///
    /// - Parameter id: The identifier to remove.
    /// - Returns: `nil` when no rule carries it; otherwise whether the rule was persisted and the
    ///   identifier of the file it owned, if it owned one.
    private func takeRule(id: UUID) -> (wasPersisted: Bool, fileID: UUID?)? {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            return (true, rules.remove(at: index).storedFileID)
        }
        if let index = transientRules.firstIndex(where: { $0.id == id }) {
            return (false, transientRules.remove(at: index).storedFileID)
        }
        return nil
    }

    /// Deletes files no surviving rule points at.
    ///
    /// Call it *after* the rule arrays have been updated, so what it sees is what will be applied.
    /// The reference check is the point: two overrides can share one body identifier — building
    /// one ``MockResponse`` and reusing it is exactly what the public API suggests — and deleting
    /// a file the other one still serves would leave it answering with an empty body forever.
    ///
    /// - Parameter ids: Candidate file identifiers. `nil` entries, from rules that owned no file,
    ///   are ignored.
    private func reclaim(_ ids: [UUID?]) {
        for id in Set(ids.compactMap { $0 }) where !isReferenced(id) {
            try? FileManager.default.removeItem(at: bodyURL(for: id))
        }
    }

    /// Whether any rule, persisted or transient, still owns this file.
    ///
    /// - Parameter id: The file identifier to look for.
    /// - Returns: `true` when some rule would be emptied by deleting it.
    private func isReferenced(_ id: UUID) -> Bool {
        (rules + transientRules).contains { $0.storedFileID == id }
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
    /// The bytes are staged at a file this store names and then renamed into place, rather than
    /// written with `Data`'s `.atomic` option. `.atomic` stages through a temporary file
    /// *Foundation* names, which survives a process death mid-write under a name neither the
    /// orphan sweep nor anything else recognises; a rename within one directory is just as atomic,
    /// and the debris of an interrupted write is `<identifier>.tmp` — a name
    /// ``sweepBodies(in:keeping:ignoringFilesNewerThan:)`` knows belongs to Scyther.
    ///
    /// - Parameter data: The body bytes.
    /// - Returns: The identifier to put in ``MockResponse/bodyID``.
    /// - Throws: Whatever creating the directory, writing the file or renaming it throws. Callers
    ///   must not carry on: a rule pointing at bytes that are not on disk answers with the stub's
    ///   status and headers and an empty body, which surfaces inside the host app as a decode
    ///   error with nothing pointing back at Scyther.
    @discardableResult
    func storeBody(_ data: Data) throws -> UUID {
        let id = UUID()
        try createBodyDirectory()
        let staging = Self.stagingURL(for: id, in: bodyDirectory)
        try data.write(to: staging)
        do {
            try FileManager.default.moveItem(at: staging, to: bodyURL(for: id))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return id
    }

    /// The suffix on the file a body is staged at while it is being written.
    nonisolated static let stagingSuffix = ".tmp"

    /// The file a body is staged at while it is being written.
    ///
    /// - Parameters:
    ///   - id: The identifier the finished file will be named after.
    ///   - directory: The body directory to stage inside, so the rename that follows stays within
    ///     one volume and is therefore atomic.
    /// - Returns: The staging file's URL.
    nonisolated static func stagingURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString)\(stagingSuffix)", isDirectory: false)
    }

    /// Copies a picked file into the rules directory and returns the copy's absolute path.
    ///
    /// A map-local override stores the copy rather than the original for two reasons. A document
    /// picked outside the app's container is only readable through a security-scoped URL, which
    /// an override cannot hold across a relaunch; and a path into somebody's Files app is not one
    /// an override can rely on tomorrow. The copy is named after a fresh identifier, exactly as a
    /// mock body is, so ``sweepOrphanedBodies()`` reclaims it once no override points at it.
    ///
    /// The read is wrapped in a security-scoped access pair, because the URL the system file
    /// importer hands back points outside the app's own container.
    ///
    /// The copy's modification date is stamped to now afterwards, because `copyItem` preserves the
    /// source's. Without the stamp the sweep's grace period protected nothing: a copy of any
    /// document last edited more than ``bodySweepGracePeriod`` ago — which is nearly every
    /// document anyone picks — was an orphan candidate the instant it was written, in the window
    /// before the override naming it is stored. The mirror case leaked instead: a document dated
    /// in the future produced a copy no sweep would ever reclaim.
    ///
    /// A copy that cannot be stamped is removed and reported as a failure rather than left in
    /// place, because a file that may be swept out from under a working override at any moment is
    /// worse than an import the developer is told did not happen.
    ///
    /// - Parameter url: The file the developer picked.
    /// - Returns: The absolute path of the copy, or `nil` when the file could not be read or the
    ///   copy could not be written.
    func storeFile(at url: URL) -> String? {
        let destination = bodyURL(for: UUID())
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try createBodyDirectory()
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            return nil
        }
        do {
            try FileManager.default.setAttributes([.modificationDate: Date()],
                                                  ofItemAtPath: destination.path)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        return destination.path
    }

    /// Creates the body directory if it is not there, and keeps it out of the host app's backup.
    ///
    /// - Throws: Whatever `createDirectory` throws. A write that carries on regardless produces a
    ///   rule pointing at bytes nothing ever wrote.
    private func createBodyDirectory() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: bodyDirectory.path) {
            try fileManager.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        }
        excludeBodyDirectoryFromBackup()
    }

    /// Marks the body directory as excluded from the host app's backup.
    ///
    /// `Application Support` is backed up to iCloud by default. A colleague's 40 MB HAR import is
    /// a debugging artefact, not the user's data, and inflating someone's backup by the size of it
    /// is not a thing a debugging tool should do.
    ///
    /// Called on **every** path that reaches the directory rather than only when creating it: a
    /// directory that already exists — which is every launch after the first — or one whose first
    /// creation failed would otherwise never be marked at all.
    ///
    /// Best effort. Failing to set the flag is not a reason to fail the write that needed the
    /// directory; the cost is a larger backup, not a broken override.
    private func excludeBodyDirectoryFromBackup() {
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

    /// How large a stored body is, without reading it.
    ///
    /// The editor decides whether a body is small enough to load into a text field, and it makes
    /// that decision on the main actor while the view is first rendering. Asking the file system
    /// for the size costs a `stat`; reading the bytes to count them costs the whole file.
    ///
    /// - Parameter id: The body identifier held by a ``MockResponse``.
    /// - Returns: The size in bytes, or `nil` when nothing has been written for that identifier.
    func bodyByteCount(for id: UUID) -> Int? {
        let values = try? bodyURL(for: id).resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }

    /// The bytes of a stored body, read without touching the main actor.
    ///
    /// `HTTPInterceptorURLProtocol` synthesises a mock response on a thread owned by the URL
    /// loading system, where awaiting the main actor risks a deadlock. This reads the same file
    /// ``bodyData(for:)`` reads, out of the body directory named by the current snapshot.
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
    ///
    /// Stands down entirely while anything is quarantined — see ``isSweepSuspended`` — because the
    /// store does not know what the developer had configured and every body on disk would look
    /// orphaned. ``removeAll()`` clears the quarantine and lets the sweep resume.
    func sweepOrphanedBodies() {
        guard !isSweepSuspended else { return }
        let directory = bodyDirectory
        Task { [weak self] in
            let candidates = await Task.detached(priority: .utility) {
                Self.orphanCandidates(in: directory, ignoringFilesNewerThan: Self.bodySweepGracePeriod)
            }.value
            self?.deleteOrphans(candidates)
        }
    }

    /// Deletes the candidates nothing references *now*.
    ///
    /// The enumeration runs off the main actor and can take a while over a big directory; the
    /// decision is taken back here, against the rules as they stand at the moment of deleting.
    /// Deciding off the main actor against a reference set captured before the walk began made the
    /// sweep a race: an override registered a few seconds after `Scyther.start()` could have its
    /// body deleted by a slow sweep that reached that directory entry a minute later, and the
    /// grace period only narrowed the window rather than closing it.
    ///
    /// - Parameter candidates: What the enumeration found, from
    ///   ``orphanCandidates(in:ignoringFilesNewerThan:)``.
    func deleteOrphans(_ candidates: [OrphanCandidate]) {
        let doomed = candidates
            .filter { candidate in
                guard let id = candidate.bodyID else { return true }
                return !isReferenced(id)
            }
            .map(\.url)
        guard !doomed.isEmpty else { return }
        Task.detached(priority: .utility) { Self.delete(doomed) }
    }

    /// How recently a body may have been written and still survive a sweep, in seconds.
    ///
    /// A body is written before the rule that points at it is stored — ``MockResponse/json(_:status:delay:)``
    /// writes when the value is *constructed* — so a host app calling `Scyther.start()` and then
    /// registering an override is briefly holding bytes nothing references yet. Without a grace
    /// period the sweep could delete a mock's body seconds before it was first used.
    nonisolated static let bodySweepGracePeriod: TimeInterval = 60

    /// Deletes every file in `directory` whose name is not a referenced identifier, along with any
    /// staging file left behind by an interrupted write.
    ///
    /// Enumerates and decides in one pass against a fixed reference set, which is right for a
    /// caller that holds one — a test, above all. ``sweepOrphanedBodies()`` uses the two halves
    /// separately so that the decision can be taken on the main actor, against the rules as they
    /// stand when the deleting actually happens.
    ///
    /// A staging file is Scyther's own — see ``storeBody(_:)`` — and is reclaimed whether or not
    /// its identifier is referenced, because a body that finished writing is not named that way.
    ///
    /// - Parameters:
    ///   - directory: The body directory to sweep.
    ///   - referenced: The identifiers rules still point at.
    ///   - ignoringFilesNewerThan: Files modified more recently than this many seconds ago are
    ///     left alone — see ``bodySweepGracePeriod``.
    nonisolated static func sweepBodies(in directory: URL,
                                        keeping referenced: Set<UUID>,
                                        ignoringFilesNewerThan grace: TimeInterval) {
        let doomed = orphanCandidates(in: directory, ignoringFilesNewerThan: grace)
            .filter { candidate in
                guard let id = candidate.bodyID else { return true }
                return !referenced.contains(id)
            }
            .map(\.url)
        delete(doomed)
    }

    /// A file in the body directory that the sweep may delete, once something decides it is
    /// unreferenced.
    struct OrphanCandidate: Sendable, Equatable {
        /// The file itself.
        let url: URL

        /// The body identifier the file is named after, or `nil` when it is the staging file of an
        /// interrupted write — which is Scyther's own debris and never referenced by anything.
        let bodyID: UUID?
    }

    /// Everything in `directory` old enough to be deleted, whether or not a rule points at it.
    ///
    /// Split out from the decision so the walk — which is the slow part — can run off the main
    /// actor while the reference check runs on it, against the rules as they stand at the moment
    /// of deleting.
    ///
    /// Deliberately conservative: a file whose name is neither a UUID nor `<UUID>.tmp` is not a
    /// candidate at all, because this walks a directory inside the host app's container and
    /// deleting something Scyther did not write would be far worse than leaving a stray file.
    ///
    /// - Parameters:
    ///   - directory: The body directory to walk.
    ///   - grace: Files modified more recently than this many seconds ago are skipped — see
    ///     ``bodySweepGracePeriod``.
    /// - Returns: The candidates, in no particular order.
    nonisolated static func orphanCandidates(in directory: URL,
                                             ignoringFilesNewerThan grace: TimeInterval) -> [OrphanCandidate] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-grace)
        return files.compactMap { file in
            let name = file.lastPathComponent
            let bodyID = UUID(uuidString: name)
            guard bodyID != nil || isStagingFile(named: name) else { return nil }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { return nil }
            return OrphanCandidate(url: file, bodyID: bodyID)
        }
    }

    /// Deletes files the sweep has decided are orphaned.
    ///
    /// - Parameter files: The files to remove. Failures are ignored: a file that has already gone,
    ///   or one the sandbox will not let go of, is not worth failing a launch over.
    nonisolated static func delete(_ files: [URL]) {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Whether a file name is one ``storeBody(_:)`` stages a body at.
    ///
    /// - Parameter name: A file name from the body directory.
    /// - Returns: `true` for `<UUID>.tmp`, which only an interrupted write leaves behind.
    nonisolated static func isStagingFile(named name: String) -> Bool {
        guard name.hasSuffix(stagingSuffix) else { return false }
        return UUID(uuidString: String(name.dropLast(stagingSuffix.count))) != nil
    }

    // MARK: - Persistence

    /// Writes the persisted rules to `UserDefaults`. Transient rules are deliberately excluded.
    ///
    /// An encode that throws is recorded as ``NetworkRuleStoreFailure/rulesNotSaved`` rather than
    /// dropped: without it the in-memory array and the published snapshot advance while
    /// `UserDefaults` keeps the previous blob, and nothing says so. Every rule is sanitised on the
    /// way in — see ``NetworkRule/sanitised`` — so the encoder should never be handed a value it
    /// refuses, but a silent write is not a thing to leave standing on the strength of "should".
    ///
    /// A blob the store could not read is moved aside here rather than overwritten, because this
    /// is the moment it would otherwise be destroyed. It is *appended* to whatever is already in
    /// quarantine: overwriting meant a second downgrade silently destroyed the configuration the
    /// first one had promised to keep.
    private func persistRules() {
        do {
            let data = try JSONEncoder().encode(rules)
            if let unreadableBlob {
                quarantine(unreadableBlob)
                self.unreadableBlob = nil
            }
            defaults.set(data, forKey: Key.rules)
            if lastFailure == .rulesNotSaved { lastFailure = nil }
        } catch {
            lastFailure = .rulesNotSaved
        }
    }

    /// The blobs earlier launches, or this one, could not read.
    ///
    /// - Returns: The quarantined blobs, oldest first, or an empty array when nothing is set aside.
    private var quarantinedBlobs: [Data] {
        defaults.array(forKey: Key.unreadableRules) as? [Data] ?? []
    }

    /// Adds one unreadable blob to the quarantine, keeping the most recent
    /// ``maximumQuarantinedBlobs``.
    ///
    /// - Parameter blob: The bytes this version could not decode.
    private func quarantine(_ blob: Data) {
        let kept = (quarantinedBlobs + [blob]).suffix(Self.maximumQuarantinedBlobs)
        defaults.set(Array(kept), forKey: Key.unreadableRules)
    }

    /// How many unreadable configurations are kept before the oldest is dropped.
    ///
    /// Preferences are not an archive, and a build that could not read the blob it wrote last
    /// launch would otherwise set one aside on every launch forever. Five is more than a
    /// downgrade-and-back needs, and the newest is kept because it is the one whose bodies are
    /// still on disk to go with it.
    nonisolated static let maximumQuarantinedBlobs = 5

    /// Whether the orphan sweep is standing down because a configuration this version could not
    /// read is set aside.
    ///
    /// The sweep deletes files no *surviving* rule points at, and the store cannot read the
    /// quarantined rules to ask what they point at — so every body belonging to them looks
    /// orphaned. Deleting those bodies would empty out the very configuration the quarantine
    /// exists to preserve, which is what happened when this was asked of the in-memory blob alone:
    /// the first mutation after the failed load cleared it, and the *next* launch's sweep — which
    /// loads a blob it can read and so has no in-memory quarantine — deleted the lot.
    ///
    /// - Note: Internal so a test can prove the sweep stood down, rather than asserting the
    ///   absence of a deletion that may simply not have happened yet. Nothing in production reads
    ///   it apart from ``sweepOrphanedBodies()``.
    var isSweepSuspended: Bool {
        unreadableBlob != nil || !quarantinedBlobs.isEmpty
    }

    /// Clears ``lastFailure`` once the developer has been told about it.
    func acknowledgeFailure() {
        lastFailure = nil
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

    /// What reading the persisted blob produced.
    private enum LoadOutcome {
        /// The blob decoded as an array. Elements this version could not understand were skipped.
        case loaded([NetworkRule])
        /// The blob is not an array this version can read at all, so there is nothing to skip.
        case unreadable
    }

    /// Decodes persisted rules, skipping any the current version cannot understand.
    ///
    /// Skipping one element is safe: the rules either side of it still load. Failing to decode the
    /// blob itself is not, because an empty list would be written straight back over the
    /// developer's whole configuration — so that case is reported rather than flattened.
    ///
    /// - Parameter data: The JSON written by ``persistRules()``, or `nil` on a first launch.
    /// - Returns: ``LoadOutcome/loaded(_:)`` with every rule that decoded cleanly, in stored order,
    ///   or ``LoadOutcome/unreadable`` when the blob is not a readable array.
    private static func decodeRules(from data: Data?) -> LoadOutcome {
        guard let data, !data.isEmpty else { return .loaded([]) }
        guard let decoded = try? JSONDecoder().decode([FailableRule].self, from: data) else {
            return .unreadable
        }
        return .loaded(decoded.compactMap(\.rule))
    }
}

internal extension NetworkRule {
    /// The identifier of the file in the rules directory this override owns, if it owns one.
    ///
    /// A mock's body and a map-local override's copy of a picked file are both written into the
    /// rules directory under a fresh identifier, so deletion and the orphan sweep treat them
    /// alike. `nil` for an override that owns no bytes, and for a map-local override pointing at
    /// a path supplied from code — which Scyther did not write and must never delete.
    var storedFileID: UUID? {
        switch actions.stub {
        case .mock(let mock):
            return mock.bodyID
        case .mapLocal(let file):
            return UUID(uuidString: URL(fileURLWithPath: file.relativePath).lastPathComponent)
        case nil:
            return nil
        }
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
