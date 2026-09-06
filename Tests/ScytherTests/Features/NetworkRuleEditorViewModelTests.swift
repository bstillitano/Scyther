//
//  NetworkRuleEditorViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkRuleEditorViewModelTests: XCTestCase {

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
        suiteName = "NetworkRuleEditorTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkRuleEditorBodies.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    func testANewRuleIsInvalidUntilItIsNamedAndPointedAtAnEndpoint() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertFalse(viewModel.isValid)
        viewModel.draft.name = "Empty cart"
        XCTAssertFalse(viewModel.isValid, "a name alone does not say which requests the override is for")
        viewModel.draft.match.path = .pattern("/api/cart")
        XCTAssertTrue(viewModel.isValid)
    }

    /// Two taps — name it, save it — used to produce an enabled override mocking every `GET` the
    /// app makes, because the draft was seeded with a method and a method counted as a facet.
    func testAMethodsOnlyDraftIsRejected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Every GET"
        viewModel.draft.match = NetworkRuleMatch(methods: ["GET"], host: nil, path: nil, query: [:])
        XCTAssertFalse(
            viewModel.isValid,
            "an override matching every GET in the app is the same hazard as one matching everything"
        )

        viewModel.save()
        XCTAssertTrue(store.rules.isEmpty)
    }

    func testANewRuleStartsWithoutAMethodSeeded() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertTrue(viewModel.draft.match.methods.isEmpty, "a new override matches any method")
    }

    func testARuleMatchingNothingIsRejected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Everything"
        viewModel.draft.match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: [:])
        XCTAssertFalse(
            viewModel.isValid,
            "a rule with no facets would match every request in the app and is almost certainly a mistake"
        )
    }

    func testSavingANewRuleAddsItToTheStore() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Empty cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.save()
        XCTAssertEqual(store.rules.map(\.name), ["Empty cart"])
    }

    // MARK: - Methods

    func testMethodsSummaryReadsAsAnyMethodWhenNothingIsSelected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = []
        XCTAssertEqual(viewModel.methodsSummary, localized("Any method"))
    }

    func testMethodsSummaryListsSelectionInTheOrderTheChecklistShowsIt() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = ["DELETE", "GET", "POST"]
        XCTAssertEqual(
            viewModel.methodsSummary,
            "GET, POST, DELETE",
            "the summary should follow availableMethods, not the set's own hashing order"
        )
    }

    func testMethodsSummaryKeepsAMethodTheChecklistDoesNotOffer() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = ["GET", "TRACE"]
        XCTAssertEqual(
            viewModel.methodsSummary,
            "GET, TRACE",
            "a method a HAR import produced must not disappear from the summary"
        )
    }

    func testTogglingAMethodAddsAndRemovesIt() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.match.methods = []
        viewModel.toggle(method: "POST")
        XCTAssertTrue(viewModel.isSelected(method: "POST"))
        viewModel.toggle(method: "POST")
        XCTAssertFalse(viewModel.isSelected(method: "POST"))
        XCTAssertEqual(viewModel.methodsSummary, localized("Any method"))
    }

    // MARK: - Saving

    func testAnInvalidDraftIsNotWrittenEvenIfSaveIsCalled() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "   "
        viewModel.save()
        XCTAssertTrue(
            store.rules.isEmpty,
            "the view disables Save, but the validity rule belongs to the view model, not the button"
        )
    }

    func testADraftMatchingNothingIsNotWrittenEvenIfSaveIsCalled() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Everything"
        viewModel.draft.match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: [:])
        viewModel.save()
        XCTAssertTrue(store.rules.isEmpty)
    }

    // MARK: - Mock bodies

    /// A saved mock rule whose body is already on disk, and the identifier it points at.
    private func savedMockRule(body: String) throws -> (rule: NetworkRule, bodyID: UUID) {
        let bodyID = try store.storeBody(Data(body.utf8))
        let rule = NetworkRule(
            name: "Cart", isEnabled: true, match: .path("/api/cart"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0)))
        )
        store.add(rule)
        return (rule, bodyID)
    }

    /// A body whose file has gone missing loads as `""`, which is what the editor opened with too,
    /// so the unchanged-body guard used to skip the rewrite however many times the developer
    /// re-saved. The override stayed broken and the editor gave no clue why.
    func testAnOverrideWhoseBodyWentMissingCanBeRepairedInTheEditor() throws {
        let saved = try savedMockRule(body: "gone")
        try FileManager.default.removeItem(at: store.bodyURL(for: saved.bodyID))

        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        XCTAssertEqual(viewModel.bodyText, "")

        XCTAssertTrue(viewModel.save())

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertNil(mock.bodyID, "an override that serves nothing should say so rather than point at nothing")
    }

    /// The sheet must not dismiss over an override that was never stored: the developer would find
    /// out from the empty list behind it.
    func testAnOverrideWhoseBodyCannotBeWrittenKeepsTheEditorOpen() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("in the way".utf8).write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        let unwritable = NetworkRuleStore(defaults: defaults,
                                          bodyDirectory: blocker.appendingPathComponent("bodies",
                                                                                        isDirectory: true))

        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: unwritable)
        viewModel.draft.name = "Cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.bodyText = "{}"

        XCTAssertFalse(viewModel.save())
        XCTAssertTrue(viewModel.didFailToSave)
        XCTAssertTrue(unwritable.rules.isEmpty)
    }

    func testEditingTheBodyDeletesTheOneItSupersedes() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        XCTAssertEqual(viewModel.bodyText, "old")

        viewModel.bodyText = "new"
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        let newBodyID = try XCTUnwrap(mock.bodyID)
        XCTAssertNotEqual(newBodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: newBodyID), Data("new".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.bodyURL(for: saved.bodyID).path),
            "the superseded body is unreachable, so leaving it behind just grows the directory"
        )
    }

    func testEmptyingTheBodyDeletesTheFileAndClearsTheIdentifier() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.bodyText = ""
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertNil(mock.bodyID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.bodyURL(for: saved.bodyID).path))
    }

    func testRemovingTheStubDeletesTheStrandedBody() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.isConditioning = true
        viewModel.stubKind = .none
        viewModel.save()

        XCTAssertNil(store.rules.first?.actions.stub)
        XCTAssertNotNil(store.rules.first?.actions.condition)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.bodyURL(for: saved.bodyID).path),
            "no rule can reach that body any more"
        )
    }

    func testResavingAnUnchangedBodyKeepsTheFileItAlreadyHad() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.draft.name = "Cart (renamed)"
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: saved.bodyID), Data("old".utf8))
    }

    func testSwitchingAwayFromAMockAndBackKeepsTheBody() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        viewModel.stubKind = .none
        viewModel.stubKind = .mock
        viewModel.save()

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, saved.bodyID)
        XCTAssertEqual(store.bodyData(for: saved.bodyID), Data("old".utf8))
    }

    // MARK: - Map local

    func testImportingAFileCopiesItAndNamesIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picked.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let picked = directory.appendingPathComponent("users.json")
        try Data("[]".utf8).write(to: picked)

        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Users"
        viewModel.draft.match = .path("/v1/users")
        viewModel.stubKind = .mapLocal
        viewModel.importMapLocalFile(from: picked)

        XCTAssertEqual(viewModel.mapLocalSummary, "users.json")
        XCTAssertEqual(viewModel.contentType, "application/json",
                       "the content type is filled in from the document's extension")
        XCTAssertFalse(viewModel.didFailToImportFile)

        guard case .mapLocal(let file) = try XCTUnwrap(viewModel.draft.actions.stub) else {
            return XCTFail("expected a map local stub")
        }
        XCTAssertNotEqual(file.path, picked.path, "the override points at the copy")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: file.path)), Data("[]".utf8))
    }

    func testImportingAFileLeavesATypedContentTypeAlone() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picked.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let picked = directory.appendingPathComponent("users.json")
        try Data("[]".utf8).write(to: picked)

        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.contentType = "text/plain"
        viewModel.importMapLocalFile(from: picked)

        XCTAssertEqual(viewModel.contentType, "text/plain")
    }

    func testImportingAFileThatCannotBeReadIsReported() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.importMapLocalFile(from: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/nothing.json"))

        XCTAssertTrue(viewModel.didFailToImportFile)
        XCTAssertEqual(viewModel.mapLocalSummary, localized("Choose File"),
                       "nothing was chosen, so the row still reads as the invitation")
    }

    // MARK: - Composing actions

    func testANewOverrideStartsAsAMockWithNothingElseSwitchedOn() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertEqual(viewModel.stubKind, .mock)
        XCTAssertFalse(viewModel.isRewritingHeaders)
        XCTAssertFalse(viewModel.isConditioning)
    }

    func testAnOverrideCanStubAndConditionAtOnce() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Slow cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.isConditioning = true
        viewModel.latency = 3
        viewModel.save()

        let saved = store.rules.first
        XCTAssertNotNil(saved?.actions.stub)
        XCTAssertEqual(saved?.actions.condition?.latency, 3)
    }

    func testTurningAnActionOffAndBackOnKeepsWhatWasTypedIntoIt() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.isConditioning = true
        viewModel.latency = 7
        viewModel.isConditioning = false
        XCTAssertNil(viewModel.draft.actions.condition)
        viewModel.isConditioning = true
        XCTAssertEqual(viewModel.latency, 7)
    }

    func testTurningTheRewriteOffAndBackOnKeepsItsHeaders() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.isRewritingHeaders = true
        viewModel.setHeaders = [NetworkRuleHeaderField(name: "Authorization", value: "Bearer test")]
        viewModel.isRewritingHeaders = false
        viewModel.isRewritingHeaders = true

        XCTAssertEqual(viewModel.draft.actions.rewriteHeaders?.set, ["Authorization": "Bearer test"])
        XCTAssertEqual(viewModel.setHeaders.map(\.name), ["Authorization"])
    }

    func testEditingHeadersWhileTheRewriteIsOffChangesNothing() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.setHeaders = [NetworkRuleHeaderField(name: "Authorization", value: "Bearer test")]
        XCTAssertNil(viewModel.draft.actions.rewriteHeaders)
    }

    func testAnOverrideWithNoActionsIsInvalid() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Inert"
        viewModel.draft.match = .path("/api/cart")
        XCTAssertTrue(viewModel.isValid)

        viewModel.stubKind = .none
        XCTAssertFalse(viewModel.isValid, "an override that matches traffic and does nothing to it")

        viewModel.isRewritingHeaders = true
        XCTAssertTrue(viewModel.isValid)
    }

    func testSavingAnInvalidOverrideWritesNothing() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Inert"
        viewModel.draft.match = .path("/api/cart")
        viewModel.stubKind = .none
        viewModel.save()
        XCTAssertTrue(store.rules.isEmpty)
    }

    // MARK: - Matching kinds

    /// A rule whose host is a wildcard, so reopening it must show Wildcard rather than Exact.
    private func wildcardHostRule() -> NetworkRule {
        NetworkRule(
            name: "Staging",
            isEnabled: true,
            match: NetworkRuleMatch(host: NetworkRulePattern(kind: .wildcard, value: "*.example.com")),
            actions: NetworkRuleActions(stub: .mock(MockResponse()))
        )
    }

    func testTheHostComparisonIsSeededFromTheOverrideBeingEdited() {
        let viewModel = NetworkRuleEditorViewModel(rule: wildcardHostRule(), store: store)
        XCTAssertEqual(viewModel.hostKind, .wildcard)
    }

    /// Clearing the field to retype it used to flip the picker back to Exact, and typing the same
    /// wildcard back saved it as an exact match on the literal `*.example.com` — which matches
    /// nothing, with no error and nothing on screen to explain why.
    func testClearingTheHostFieldKeepsTheComparisonItWasSavedWith() {
        let viewModel = NetworkRuleEditorViewModel(rule: wildcardHostRule(), store: store)
        viewModel.hostText = ""
        XCTAssertEqual(viewModel.hostKind, .wildcard, "clearing the text must not downgrade the comparison")

        viewModel.hostText = "*.example.com"
        XCTAssertEqual(viewModel.draft.match.host, NetworkRulePattern(kind: .wildcard, value: "*.example.com"))
    }

    func testClearingThePathFieldKeepsTheComparisonItWasSavedWith() {
        let rule = NetworkRule(
            name: "Cart",
            isEnabled: true,
            match: NetworkRuleMatch(path: NetworkRulePattern(kind: .contains, value: "/cart")),
            actions: NetworkRuleActions(stub: .mock(MockResponse()))
        )
        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        XCTAssertEqual(viewModel.pathKind, .contains)

        viewModel.pathText = ""
        XCTAssertEqual(viewModel.pathKind, .contains)

        viewModel.pathText = "/cart"
        XCTAssertEqual(viewModel.draft.match.path, NetworkRulePattern(kind: .contains, value: "/cart"))
    }

    // MARK: - Match everything

    func testAWildcardOfNothingButStarsIsRejected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Everything"
        viewModel.pathKind = .wildcard
        viewModel.pathText = "*"
        XCTAssertFalse(viewModel.isValid, "two taps and one character must not produce an app-wide override")

        viewModel.pathText = "/v1/*"
        XCTAssertTrue(viewModel.isValid)
    }

    func testAContainsPathOfASlashIsRejected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Everything"
        viewModel.pathKind = .contains
        viewModel.pathText = "/"
        XCTAssertFalse(viewModel.isValid, "every URL path begins with a slash")
    }

    func testAWildcardHostOfNothingButStarsIsRejected() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Everything"
        viewModel.hostKind = .wildcard
        viewModel.hostText = "**"
        XCTAssertFalse(viewModel.isValid)
    }

    /// A host is never spelled with a slash in it, so `Contains /` on the *host* matches nothing
    /// rather than everything — a different mistake, and not one this guard is about.
    func testAContainsHostOfASlashIsStillAFacet() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Odd but narrow"
        viewModel.hostKind = .contains
        viewModel.hostText = "/"
        XCTAssertTrue(viewModel.isValid)
    }

    // MARK: - Bodies that are not text

    /// Bytes that are not valid UTF-8 — the first six of a JPEG.
    private static let binaryBody = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    func testABodyThatIsNotTextIsNotOfferedForTextEditing() throws {
        let bodyID = try store.storeBody(Self.binaryBody)
        let rule = NetworkRule(
            name: "Avatar", isEnabled: true, match: .path("/v1/avatar"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0)))
        )
        store.add(rule)

        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        XCTAssertEqual(viewModel.bodyEditability, .notText)
        XCTAssertEqual(viewModel.bodySummary, localized("\(Self.binaryBody.count) bytes"),
                       "the summary reports the stored file, not a lossy decode of it")
    }

    /// One tap from **Save as mock** on a captured image: the field was loaded with a lossy decode,
    /// so touching it at all wrote every non-UTF-8 byte back as a replacement character.
    func testEditingIsRefusedRatherThanCorruptingABodyThatIsNotText() throws {
        let bodyID = try store.storeBody(Self.binaryBody)
        let rule = NetworkRule(
            name: "Avatar", isEnabled: true, match: .path("/v1/avatar"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0)))
        )
        store.add(rule)

        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        viewModel.bodyText = "clobbered"
        XCTAssertTrue(viewModel.save())

        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, bodyID, "the override still points at the bytes it was built from")
        XCTAssertEqual(store.bodyData(for: bodyID), Self.binaryBody)
    }

    /// **Save as mock** carries the captured bytes rather than writing them, so the same check has
    /// to reach a body that has never been on disk.
    func testPendingBytesThatAreNotTextAreNotOfferedForTextEditing() {
        var mock = MockResponse()
        mock.pendingBody = Self.binaryBody
        let rule = NetworkRule(name: "Avatar", isEnabled: false, match: .path("/v1/avatar"),
                               actions: NetworkRuleActions(stub: .mock(mock)))

        let viewModel = NetworkRuleEditorViewModel(prefilled: rule, store: store)
        XCTAssertEqual(viewModel.bodyEditability, .notText)
        XCTAssertEqual(viewModel.bodyText, "")

        viewModel.bodyText = "clobbered"
        XCTAssertTrue(viewModel.save())

        guard case .mock(let saved) = try? XCTUnwrap(store.rules.first).actions.stub,
              let bodyID = saved.bodyID else {
            return XCTFail("expected a stored mock body")
        }
        XCTAssertEqual(store.bodyData(for: bodyID), Self.binaryBody)
    }

    /// The editor is opened by the view's first render, on the main actor, so a body too big to
    /// edit comfortably must not be read and decoded there.
    func testABodyTooLargeToEditIsNotReadIntoTheEditor() throws {
        let bytes = Data(repeating: UInt8(ascii: "x"),
                         count: NetworkRuleEditorViewModel.maximumEditableBodyBytes + 1)
        let bodyID = try store.storeBody(bytes)
        let rule = NetworkRule(
            name: "Big", isEnabled: true, match: .path("/v1/big"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0)))
        )
        store.add(rule)

        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        XCTAssertEqual(viewModel.bodyEditability, .tooLarge)
        XCTAssertEqual(viewModel.bodyText, "")
        XCTAssertEqual(viewModel.bodySummary, localized("\(bytes.count) bytes"))

        XCTAssertTrue(viewModel.save())
        guard case .mock(let mock) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.bodyID, bodyID, "an oversized body survives a save that never loaded it")
    }

    func testAnOrdinaryTextBodyStaysEditable() throws {
        let saved = try savedMockRule(body: "old")
        let viewModel = NetworkRuleEditorViewModel(rule: saved.rule, store: store)
        XCTAssertEqual(viewModel.bodyEditability, .editable)
        XCTAssertEqual(viewModel.bodySummary, localized("\(3) bytes"))
    }

    // MARK: - Confirming twice

    /// The confirm button is tappable until the sheet dismisses, so the second tap has to be a
    /// no-op rather than a second write of the same bytes.
    func testConfirmingTwiceStoresOneOverrideAndOneBody() throws {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.bodyText = "{}"

        XCTAssertTrue(viewModel.save())
        guard case .mock(let first) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        let firstBodyID = try XCTUnwrap(first.bodyID)

        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(store.rules.count, 1)
        guard case .mock(let second) = try XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(second.bodyID, firstBodyID, "the second tap must not write a second copy")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bodyDirectory.path).count, 1)
    }

    // MARK: - Ranges

    func testAStatusCodeOutsideTheHTTPRangeIsClampedBeforeItIsStored() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Cart"
        viewModel.draft.match = .path("/api/cart")

        viewModel.statusCode = 700
        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(viewModel.statusCode, 599)

        viewModel.statusCode = -1
        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(viewModel.statusCode, 100)
    }

    func testANegativeOrNotANumberDelayIsStoredAsZero() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Cart"
        viewModel.draft.match = .path("/api/cart")

        viewModel.delay = -5
        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(viewModel.delay, 0, "a negative delay meant zero anyway, so say so")

        viewModel.delay = .nan
        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(viewModel.delay, 0)
    }

    func testAConditionsLatencyAndFailureRateAreBroughtIntoRange() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Cart"
        viewModel.draft.match = .path("/api/cart")
        viewModel.isConditioning = true
        viewModel.latency = -1
        viewModel.failureRate = 4

        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(store.rules.first?.actions.condition?.latency, 0)
        XCTAssertEqual(store.rules.first?.actions.condition?.failureRate, 1)
    }

    func testTheContentTypeIsTrimmedLikeTheHostAndPath() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.draft.name = "Users"
        viewModel.draft.match = .path("/v1/users")
        viewModel.stubKind = .mapLocal
        viewModel.contentType = "  application/json  "

        XCTAssertTrue(viewModel.save())
        guard case .mapLocal(let file) = try? XCTUnwrap(store.rules.first).actions.stub else {
            return XCTFail("expected a map local stub")
        }
        XCTAssertEqual(file.contentType, "application/json")
    }

    // MARK: - Content type picker

    /// A file picked in the editor, written where the file importer would have handed it back.
    private func pickedFile(named name: String, contents: String = "[]") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picked.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testEveryOfferedContentTypeIsDistinct() {
        let types = NetworkRuleEditorViewModel.contentTypes
        XCTAssertEqual(Set(types).count, types.count)
        XCTAssertTrue(types.contains("application/json"))
    }

    /// A developer picking `users.json` should not have to tell us it is JSON.
    func testPickingAJSONFileSelectsTheJSONEntryRatherThanCustom() throws {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.importMapLocalFile(from: try pickedFile(named: "users.json"))

        XCTAssertEqual(viewModel.contentType, "application/json")
        XCTAssertEqual(viewModel.contentTypeSelection, .listed("application/json"))
        XCTAssertFalse(viewModel.isCustomContentType)
    }

    func testAContentTypeOutsideTheOfferedSetReadsAsCustom() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.contentType = "application/vnd.example+json"

        XCTAssertTrue(viewModel.isCustomContentType)
        XCTAssertEqual(viewModel.contentTypeSelection, .custom)
    }

    func testChoosingCustomKeepsWhatTheEntryAlreadyHeld() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.contentTypeSelection = .listed("text/csv")
        XCTAssertEqual(viewModel.contentType, "text/csv")

        viewModel.contentTypeSelection = .custom
        XCTAssertTrue(viewModel.isCustomContentType, "Custom reveals the field rather than clearing it")
        XCTAssertEqual(viewModel.contentType, "text/csv")

        viewModel.contentTypeSelection = .listed("application/json")
        XCTAssertFalse(viewModel.isCustomContentType)
        XCTAssertEqual(viewModel.contentType, "application/json")
    }

    /// A map local stub with no content type starts at None, not Custom: Custom would reveal an
    /// empty field for a value the developer has not decided to give.
    func testANewMapLocalOverrideStartsWithNoContentType() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal

        XCTAssertEqual(viewModel.contentTypeSelection, .unset)
        XCTAssertFalse(viewModel.isCustomContentType, "the Custom field stays hidden until it is chosen")
        XCTAssertEqual(viewModel.contentType, "")
    }

    /// Choosing None after a type was set clears it, so the header is omitted again.
    func testChoosingNoneClearsTheContentType() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        viewModel.contentTypeSelection = .listed("application/json")

        viewModel.contentTypeSelection = .unset

        XCTAssertEqual(viewModel.contentType, "")
        XCTAssertFalse(viewModel.isCustomContentType)
    }

    func testReopeningAMapLocalOverrideSeedsThePickerFromWhatWasStored() {
        let rule = NetworkRule(
            name: "Users", isEnabled: true, match: .path("/v1/users"),
            actions: NetworkRuleActions(stub: .mapLocal(MapLocalFile(path: "/tmp/users.json",
                                                                     fileName: "users.json",
                                                                     contentType: "application/json")))
        )
        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        XCTAssertEqual(viewModel.contentTypeSelection, .listed("application/json"))
        XCTAssertFalse(viewModel.isCustomContentType)
    }

    // MARK: - Choosing a file

    /// The section used to carry a `File` row and a `Choose File` button saying the same thing
    /// twice. One row now does both, so it has to read as the invitation while nothing is chosen.
    func testTheFileRowInvitesAChoiceWhileNothingIsChosen() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        viewModel.stubKind = .mapLocal
        XCTAssertEqual(viewModel.mapLocalSummary, localized("Choose File"))
    }

    func testSavingAnExistingRuleUpdatesItInPlace() {
        var rule = NetworkRule(
            id: UUID(), name: "Old", isEnabled: true, match: .path("/api/cart"),
            actions: NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)))
        )
        store.add(rule)
        rule.name = "New"
        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        viewModel.save()
        XCTAssertEqual(store.rules.map(\.name), ["New"])
        XCTAssertEqual(store.rules.count, 1)
    }
}
