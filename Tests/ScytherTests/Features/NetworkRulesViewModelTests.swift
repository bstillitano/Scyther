//
//  NetworkRulesViewModelTests.swift
//  ScytherTests
//

import Combine
@testable import Scyther
import XCTest

@MainActor
final class NetworkRulesViewModelTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var bodyDirectory: URL!
    nonisolated(unsafe) private var createdStore: NetworkRuleStore?

    /// A store isolated to this test's own suite and body directory.
    ///
    /// Built on first use rather than in `setUpWithError()`, which is nonisolated and so cannot
    /// construct a main-actor type.
    private var store: NetworkRuleStore {
        if let createdStore { return createdStore }
        let store = NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
        createdStore = store
        return store
    }

    override func setUpWithError() throws {
        suiteName = "NetworkRulesViewModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkRulesViewModelBodies.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    /// A named rule matching one path, with whatever action is asked for.
    private func rule(
        named name: String,
        isEnabled: Bool = true,
        actions: NetworkRuleActions = NetworkRuleActions(stub: .mock(MockResponse()))
    ) -> NetworkRule {
        NetworkRule(name: name, isEnabled: isEnabled, match: .path("/api/\(name)"), actions: actions)
    }

    // MARK: - Row presentation

    func testSubtitleNamesTheOnlyAction() {
        let viewModel = NetworkRulesViewModel(store: store)
        XCTAssertEqual(viewModel.subtitle(for: rule(named: "cart")), localized("Mock Response"))
    }

    func testSubtitleNamesEveryActionAnOverrideCarries() {
        let viewModel = NetworkRulesViewModel(store: store)
        let composed = rule(named: "cart", actions: NetworkRuleActions(
            stub: .mock(MockResponse()),
            rewriteHeaders: NetworkHeaderRewrite(set: ["A": "1"]),
            condition: NetworkCondition(latency: 1)
        ))
        XCTAssertEqual(
            viewModel.subtitle(for: composed),
            [localized("Mock Response"), localized("Rewrite Headers"), localized("Network Condition")]
                .joined(separator: " \u{00B7} ")
        )
    }

    /// The subtitle no longer carries the enabled state: the row shows that by reading as
    /// disabled, so saying it in words as well would be saying it twice.
    func testSubtitleSaysNothingAboutTheEnabledState() {
        let viewModel = NetworkRulesViewModel(store: store)
        let enabled = rule(named: "cart", isEnabled: true)
        let disabled = rule(named: "cart", isEnabled: false)
        XCTAssertEqual(viewModel.subtitle(for: enabled), viewModel.subtitle(for: disabled))
    }

    func testSubtitleSaysSoWhenAnOverrideDoesNothing() {
        let viewModel = NetworkRulesViewModel(store: store)
        let inert = rule(named: "cart", actions: NetworkRuleActions())
        XCTAssertEqual(viewModel.subtitle(for: inert), localized("No actions"))
    }

    /// A HAR document with `count` entries, each a distinct GET.
    private func har(entries count: Int) -> String {
        let entries = (0..<count).map { index in
            """
            {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
             "request":{"method":"GET","url":"https://api.example.com/v1/item\(index)","httpVersion":"HTTP/1.1",
                        "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
             "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                         "headers":[],"content":{"size":0,"mimeType":"","text":null},
                         "redirectURL":"","headersSize":-1,"bodySize":0},
             "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
            """
        }.joined(separator: ",")
        return """
        {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[\(entries)]}}
        """
    }

    /// Writes `contents` to a throwaway file inside this test's own body directory.
    private func writeFile(_ contents: String, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        let url = bodyDirectory.appendingPathComponent(name, isDirectory: false)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Mirroring the store

    func testTheListMirrorsRulesAddedToTheStoreAfterwards() throws {
        let viewModel = NetworkRulesViewModel(store: store)
        XCTAssertTrue(viewModel.rules.isEmpty)
        store.add(rule(named: "cart"))
        XCTAssertEqual(viewModel.rules.map(\.name), ["cart"])
        store.remove(id: try XCTUnwrap(viewModel.rules.first).id)
        XCTAssertTrue(viewModel.rules.isEmpty)
    }

    func testTheMasterSwitchReadsAndWritesThroughToTheStore() {
        let viewModel = NetworkRulesViewModel(store: store)
        XCTAssertTrue(viewModel.isEnabled)
        viewModel.isEnabled = false
        XCTAssertFalse(store.isEnabled, "the store stays the single writer of the master switch")
        store.isEnabled = true
        XCTAssertTrue(viewModel.isEnabled)
    }

    // MARK: - Transient overrides

    func testTransientOverridesAreListedSeparatelyFromPersistedOnes() {
        let viewModel = NetworkRulesViewModel(store: store)
        store.add(rule(named: "saved"))
        store.addTransient(rule(named: "from code"))
        XCTAssertEqual(viewModel.rules.map(\.name), ["saved"])
        XCTAssertEqual(viewModel.transientRules.map(\.name), ["from code"])
    }

    func testTheEmptyStateHidesWhileOnlyTransientOverridesExist() {
        let viewModel = NetworkRulesViewModel(store: store)
        XCTAssertTrue(viewModel.isEmpty)
        store.addTransient(rule(named: "from code"))
        XCTAssertFalse(
            viewModel.isEmpty,
            "an override registered in code is being applied to live traffic and must be visible"
        )
    }

    // MARK: - Enabling

    func testSettingAnOverrideEnabledWritesItBackToTheStore() throws {
        let viewModel = NetworkRulesViewModel(store: store)
        let saved = rule(named: "cart", isEnabled: true)
        store.add(saved)
        viewModel.setEnabled(saved, to: false)
        XCTAssertEqual(store.rules.map(\.isEnabled), [false])
        viewModel.setEnabled(try XCTUnwrap(store.rules.first), to: true)
        XCTAssertEqual(store.rules.map(\.isEnabled), [true])
    }

    // MARK: - Reordering

    func testMovingAnOverrideChangesItsPrecedenceInTheStore() {
        let viewModel = NetworkRulesViewModel(store: store)
        ["first", "second", "third"].forEach { store.add(rule(named: $0)) }
        viewModel.move(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.rules.map(\.name), ["third", "first", "second"])
    }

    // MARK: - Deletion

    func testSwipingRecordsADeletionRatherThanPerformingIt() {
        let viewModel = NetworkRulesViewModel(store: store)
        store.add(rule(named: "cart"))
        viewModel.requestDeletion(at: IndexSet(integer: 0))
        XCTAssertEqual(viewModel.pendingDeletions.map(\.name), ["cart"])
        XCTAssertEqual(store.rules.count, 1, "nothing is deleted until the alert is confirmed")
    }

    func testTheRowsDeleteButtonRecordsTheOverrideItNamed() {
        let viewModel = NetworkRulesViewModel(store: store)
        let saved = rule(named: "cart")
        store.add(saved)
        viewModel.requestDeletion(of: saved)
        XCTAssertEqual(viewModel.pendingDeletions, [saved])
    }

    func testConfirmingRemovesTheOverrideAndDismissesTheAlert() {
        let viewModel = NetworkRulesViewModel(store: store)
        store.add(rule(named: "cart"))
        viewModel.requestDeletion(at: IndexSet(integer: 0))
        viewModel.confirmDeletion()
        XCTAssertTrue(store.rules.isEmpty)
        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
    }

    func testCancellingLeavesTheOverrideAlone() {
        let viewModel = NetworkRulesViewModel(store: store)
        store.add(rule(named: "cart"))
        viewModel.requestDeletion(at: IndexSet(integer: 0))
        viewModel.cancelDeletion()
        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
        XCTAssertEqual(store.rules.count, 1)
    }

    func testRequestingDeletionOfAnOffsetThatIsGoneRecordsNothing() {
        let viewModel = NetworkRulesViewModel(store: store)
        viewModel.requestDeletion(at: IndexSet(integer: 4))
        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
    }

    func testDeletingTwoRowsAtOnceDeletesBothOfThem() {
        let viewModel = NetworkRulesViewModel(store: store)
        ["first", "second", "third"].forEach { store.add(rule(named: $0)) }
        viewModel.requestDeletion(at: IndexSet([0, 2]))
        XCTAssertEqual(viewModel.pendingDeletions.map(\.name), ["first", "third"])
        viewModel.confirmDeletion()
        XCTAssertEqual(
            store.rules.map(\.name),
            ["second"],
            "an offset set can hold several rows and none of them may be silently dropped"
        )
    }

    func testDeletingTwoRowsSkipsAnOffsetThatIsNoLongerThere() {
        let viewModel = NetworkRulesViewModel(store: store)
        store.add(rule(named: "only"))
        viewModel.requestDeletion(at: IndexSet([0, 9]))
        XCTAssertEqual(viewModel.pendingDeletions.map(\.name), ["only"])
    }

    func testTheAlertNamesASingleOverrideAndCountsSeveral() {
        let viewModel = NetworkRulesViewModel(store: store)
        ["first", "second"].forEach { store.add(rule(named: $0)) }

        viewModel.requestDeletion(at: IndexSet(integer: 0))
        XCTAssertEqual(viewModel.deletionTitle, localized("Delete first?"))

        viewModel.requestDeletion(at: IndexSet([0, 1]))
        XCTAssertEqual(viewModel.deletionTitle, localized("Delete \(2) overrides?"))
    }

    // MARK: - Importing

    func testImportingAHARAddsEveryEntryAndReportsTheCount() async throws {
        let viewModel = NetworkRulesViewModel(store: store)
        let url = try writeFile(har(entries: 3), named: "three.har")
        await viewModel.importHAR(from: url)
        XCTAssertEqual(store.rules.count, 3)
        XCTAssertEqual(viewModel.importOutcome, .imported(count: 3, skipped: 0))
        XCTAssertTrue(store.rules.allSatisfy { !$0.isEnabled }, "imported overrides arrive disabled")
    }

    /// A capture in which not every entry can be read still imports the ones that can, and the
    /// alert says how many were lost: 1 of 2 is a partial success, not a success.
    func testImportingAHARWithAnUnreadableEntryReportsWhatWasLost() async throws {
        let viewModel = NetworkRulesViewModel(store: store)
        let partial = """
        {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com/v1/aborted","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}},
          {"startedDateTime":"2026-09-05T00:00:00.000Z","time":1,
           "request":{"method":"GET","url":"https://api.example.com/v1/ok","httpVersion":"HTTP/1.1",
                      "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
           "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","cookies":[],
                       "headers":[],"content":{"size":0,"mimeType":"","text":null},
                       "redirectURL":"","headersSize":-1,"bodySize":0},
           "cache":{},"timings":{"send":0,"wait":1,"receive":0}}
        ]}}
        """
        let url = try writeFile(partial, named: "partial.har")
        await viewModel.importHAR(from: url)
        XCTAssertEqual(store.rules.count, 1, "the readable entry must still be imported")
        XCTAssertEqual(viewModel.importOutcome, .imported(count: 1, skipped: 1))
    }

    /// The alert names the skipped entries only when there were some, and two outcomes that
    /// differ in either number are different alerts.
    func testTheImportAlertNamesTheSkippedEntriesOnlyWhenThereAreSome() {
        let clean = NetworkRuleImportOutcome.imported(count: 3, skipped: 0)
        let partial = NetworkRuleImportOutcome.imported(count: 3, skipped: 2)
        XCTAssertEqual(clean.message,
                       localized("Imported \(3) overrides. Every imported override starts disabled."))
        XCTAssertTrue(partial.message.hasPrefix(clean.message), "the count sentence is unchanged")
        XCTAssertTrue(partial.message.contains(localized("\(2) entries could not be read.")),
                      "a developer given 3 of 5 overrides has to be told about the other 2")
        XCTAssertNotEqual(clean.id, partial.id, "the alert must redraw when the numbers differ")
    }

    func testImportingAFileThatIsNotAHARReportsFailure() async throws {
        let viewModel = NetworkRulesViewModel(store: store)
        let url = try writeFile("not json", named: "broken.har")
        await viewModel.importHAR(from: url)
        XCTAssertEqual(viewModel.importOutcome, .failed)
        XCTAssertTrue(store.rules.isEmpty)
    }

    func testImportingAFileThatIsNotThereReportsFailure() async {
        let viewModel = NetworkRulesViewModel(store: store)
        await viewModel.importHAR(from: bodyDirectory.appendingPathComponent("missing.har"))
        XCTAssertEqual(viewModel.importOutcome, .failed)
    }

    func testAFailureRaisedByTheFileImporterItselfIsReported() {
        let viewModel = NetworkRulesViewModel(store: store)
        viewModel.reportImportFailure()
        XCTAssertEqual(viewModel.importOutcome, .failed)
    }

    func testImportingManyEntriesPublishesOnceRatherThanOncePerEntry() async throws {
        let viewModel = NetworkRulesViewModel(store: store)
        var publications = 0
        let cancellable = store.$rules.dropFirst().sink { _ in publications += 1 }
        defer { cancellable.cancel() }

        let url = try writeFile(har(entries: 25), named: "many.har")
        await viewModel.importHAR(from: url)

        XCTAssertEqual(store.rules.count, 25)
        XCTAssertEqual(
            publications,
            1,
            "each publication is a full JSON encode of the rules array into UserDefaults, a fresh "
            + "interceptor snapshot and a list rebuild; a HAR import must cost exactly one"
        )
    }
}
