//
//  LogDetailsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class LogDetailsViewModelTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var bodyDirectory: URL!

    override func setUpWithError() throws {
        suiteName = "LogDetailsViewModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkRuleBodies.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    private func makeStore() -> NetworkRuleStore {
        NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
    }

    /// A capture of a real `GET` that returned JSON, with its response body written to disk.
    private func makeCapture(
        url: String = "https://api.example.com/v1/users?page=2",
        method: String = "GET",
        statusCode: Int = 201,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: String = #"{"id":1}"#
    ) throws -> HTTPRequest {
        let request = HTTPRequest()
        request.requestURL = url
        request.requestMethod = method
        request.requestTime = "10:00:00.000"
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: url)),
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
        request.saveResponse(response, data: Data(body.utf8))
        return request
    }

    // MARK: - Existing behaviour

    func testGraphQLFieldsPopulatedOnFirstAppear() async {
        let request = HTTPRequest()
        request.isGraphQL = true
        request.graphQLOperationName = "GetUser"
        request.graphQLOperationType = .mutation

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertTrue(viewModel.hasGraphQL)
        XCTAssertEqual(viewModel.graphQLOperationName, "GetUser")
        XCTAssertEqual(viewModel.graphQLOperationType, "Mutation")
    }

    func testCurlRequestPopulatedOnFirstAppear() async {
        let request = HTTPRequest()
        request.requestCurl = "curl -X GET 'https://api.example.com/users'"

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertEqual(viewModel.curlRequest, "curl -X GET 'https://api.example.com/users'")
    }

    func testCurlRequestDefaultsToEmptyWhenMissing() async {
        let request = HTTPRequest()
        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()
        XCTAssertEqual(viewModel.curlRequest, "")
    }

    func testNonGraphQLHasNoGraphQLSection() async {
        let request = HTTPRequest()
        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()
        XCTAssertFalse(viewModel.hasGraphQL)
    }

    // MARK: - Replay rows

    /// The defect W23 named, at the surface it reaches the developer through.
    func testAReplayRowNamesWhatShapedEitherSide() throws {
        let original = HTTPRequest()
        original.responseCode = 200
        original.requestMethod = "GET"
        let replay = HTTPRequest()
        replay.responseCode = 200
        replay.requestMethod = "GET"
        replay.wasStubbed = true

        let link = ReplayLink(replay: replay, original: original)

        XCTAssertEqual(link.note, "Replay: MOCKED")
        XCTAssertFalse(link.comparison.isLikeForLike)
    }

    func testAReplayRowOfUntouchedTrafficHasNoNote() {
        let original = HTTPRequest()
        original.responseCode = 200
        let replay = HTTPRequest()
        replay.responseCode = 200
        XCTAssertNil(ReplayLink(replay: replay, original: original).note)
    }

    func testAReplayRowNamesBothSidesWhenBothWereShaped() {
        let original = HTTPRequest()
        original.responseCode = 200
        original.breakpointNames = ["cart"]
        let replay = HTTPRequest()
        replay.responseCode = 200
        replay.appliedRuleNames = ["Slow cart"]
        XCTAssertEqual(ReplayLink(replay: replay, original: original).note,
                       "Original: HELD · Replay: OVERRIDDEN")
    }

    // MARK: - Applied overrides

    func testAppliedRuleNamesPopulatedOnFirstAppear() async {
        let request = HTTPRequest()
        request.appliedRuleNames = ["Empty cart", "Slow network"]

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertEqual(viewModel.appliedRuleNames, ["Empty cart", "Slow network"])
    }

    func testAppliedRuleNamesEmptyWhenNoOverrideApplied() async {
        let viewModel = LogDetailsViewModel(httpRequest: HTTPRequest())
        await viewModel.onFirstAppear()
        XCTAssertTrue(viewModel.appliedRuleNames.isEmpty)
    }

    func testWasStubbedPopulatedOnFirstAppear() async {
        let request = HTTPRequest()
        request.wasStubbed = true

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertTrue(viewModel.wasStubbed)
    }

    // MARK: - Save as mock availability

    func testCanSaveAsMockOnceAResponseArrived() async throws {
        let viewModel = LogDetailsViewModel(httpRequest: try makeCapture())
        await viewModel.onFirstAppear()
        XCTAssertTrue(viewModel.canSaveAsMock)
    }

    func testCannotSaveAsMockBeforeLoading() throws {
        let viewModel = LogDetailsViewModel(httpRequest: try makeCapture())
        XCTAssertFalse(viewModel.canSaveAsMock)
    }

    func testCannotSaveAsMockWithoutAResponse() async {
        let request = HTTPRequest()
        request.requestURL = "https://api.example.com/v1/users"
        request.requestMethod = "GET"

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertFalse(viewModel.canSaveAsMock)
    }

    func testCannotSaveAStubbedResponseAsMock() async throws {
        let request = try makeCapture()
        request.wasStubbed = true

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertFalse(viewModel.canSaveAsMock)
    }

    // MARK: - Building the mock

    func testMakeMockRuleStartsDisabledAndNamedAfterTheCapture() async throws {
        let viewModel = LogDetailsViewModel(httpRequest: try makeCapture(), store: makeStore())
        await viewModel.onFirstAppear()

        let rule = viewModel.makeMockRule()

        XCTAssertFalse(rule.isEnabled)
        XCTAssertEqual(rule.name, "GET /v1/users")
    }

    func testMakeMockRuleMatchesTheCapturedMethodHostAndPath() async throws {
        let capture = try makeCapture(url: "https://api.example.com/v1/users?page=2", method: "post")
        let viewModel = LogDetailsViewModel(httpRequest: capture, store: makeStore())
        await viewModel.onFirstAppear()

        let match = viewModel.makeMockRule().match

        XCTAssertEqual(match.methods, ["POST"])
        XCTAssertEqual(match.host, NetworkRulePattern(kind: .exact, value: "api.example.com"))
        XCTAssertEqual(match.path, NetworkRulePattern(kind: .exact, value: "/v1/users"))
        XCTAssertTrue(match.query.isEmpty, "the query is left unconstrained so the mock is not pinned to one page")
    }

    func testMakeMockRuleCarriesTheCapturedStatusHeadersAndBody() async throws {
        let store = makeStore()
        let capture = try makeCapture(
            statusCode: 201,
            headers: ["Content-Type": "application/json", "X-Request-Id": "abc"],
            body: #"{"id":1}"#
        )
        let viewModel = LogDetailsViewModel(httpRequest: capture, store: store)
        await viewModel.onFirstAppear()

        guard case .mock(let mock) = viewModel.makeMockRule().actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.statusCode, 201)
        XCTAssertEqual(mock.headers["Content-Type"], "application/json")
        XCTAssertEqual(mock.headers["X-Request-Id"], "abc")
        XCTAssertEqual(mock.delay, 0)

        // The bytes travel with the override rather than being written here, so abandoning the
        // editor the rule opens leaves nothing on disk to reclaim.
        XCTAssertNil(mock.bodyID)
        XCTAssertEqual(mock.pendingBody, Data(#"{"id":1}"#.utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bodyDirectory.path),
                       "building the override writes nothing")

        XCTAssertTrue(store.add(viewModel.makeMockRule()))
        guard case .mock(let stored) = store.rules.first?.actions.stub else {
            return XCTFail("expected the stored override to carry a mock")
        }
        let bodyID = try XCTUnwrap(stored.bodyID, "the store writes the bytes when it takes the rule")
        XCTAssertEqual(store.bodyData(for: bodyID), Data(#"{"id":1}"#.utf8))
    }

    func testMakeMockRuleDropsHeadersDescribingTheWireEncoding() async throws {
        let capture = try makeCapture(headers: [
            "Content-Type": "application/json",
            "Content-Encoding": "gzip",
            "Content-Length": "1234",
            "Transfer-Encoding": "chunked"
        ])
        let viewModel = LogDetailsViewModel(httpRequest: capture, store: makeStore())
        await viewModel.onFirstAppear()

        guard case .mock(let mock) = viewModel.makeMockRule().actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertEqual(mock.headers, ["Content-Type": "application/json"])
    }

    func testMakeMockRuleWithoutABodyStoresNothing() async throws {
        let store = makeStore()
        let capture = try makeCapture(statusCode: 204, headers: [:], body: "")
        let viewModel = LogDetailsViewModel(httpRequest: capture, store: store)
        await viewModel.onFirstAppear()

        guard case .mock(let mock) = viewModel.makeMockRule().actions.stub else {
            return XCTFail("expected a mock action")
        }
        XCTAssertNil(mock.bodyID)
        XCTAssertEqual(mock.statusCode, 204)
    }

    func testMakeMockRuleFallsBackToRootWhenTheURLIsUnusable() async throws {
        let request = HTTPRequest()
        request.requestMethod = "GET"
        request.requestTime = "10:00:00.000"
        request.responseCode = 200

        let viewModel = LogDetailsViewModel(httpRequest: request, store: makeStore())
        await viewModel.onFirstAppear()

        let rule = viewModel.makeMockRule()
        XCTAssertEqual(rule.name, "GET /")
        XCTAssertNil(rule.match.host)
        XCTAssertEqual(rule.match.path, NetworkRulePattern(kind: .exact, value: "/"))
        XCTAssertEqual(rule.match.methods, ["GET"])
    }

    func testMakeMockRuleIsValidInTheEditor() async throws {
        let store = makeStore()
        let viewModel = LogDetailsViewModel(httpRequest: try makeCapture(), store: store)
        await viewModel.onFirstAppear()

        let editor = NetworkRuleEditorViewModel(prefilled: viewModel.makeMockRule(), store: store)
        XCTAssertTrue(editor.isValid)
    }

    func testSavingTheMockAddsItRatherThanSilentlyDoingNothing() async throws {
        let store = makeStore()
        let viewModel = LogDetailsViewModel(httpRequest: try makeCapture(), store: store)
        await viewModel.onFirstAppear()

        let editor = NetworkRuleEditorViewModel(prefilled: viewModel.makeMockRule(), store: store)
        editor.save()

        XCTAssertEqual(store.rules.map(\.name), ["GET /v1/users"])
        XCTAssertEqual(store.rules.first?.isEnabled, false)
    }
}

// MARK: - Replays

@MainActor
final class LogDetailsViewModelReplayTests: XCTestCase {

    /// A URL nothing else in the suite uses, because the network log is shared across the run.
    private func uniqueURL() -> String {
        "https://api.example.com/v1/replay/\(UUID().uuidString)"
    }

    private func capture(url: String, stubbed: Bool = false, replayOf: String? = nil) throws -> HTTPRequest {
        let request = HTTPRequest()
        request.requestURL = url
        request.requestMethod = "GET"
        request.requestTime = "10:00:00.000"
        request.wasStubbed = stubbed
        request.replayOfID = replayOf
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: url)),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        request.saveResponse(response, data: Data(#"{"id":1}"#.utf8))
        return request
    }

    func testReplayIsOfferedForACapturedRequest() async throws {
        let viewModel = LogDetailsViewModel(httpRequest: try capture(url: uniqueURL()))
        await viewModel.onFirstAppear()
        XCTAssertTrue(viewModel.canReplay)
    }

    func testReplayIsNotOfferedForASynthesisedResponse() async throws {
        let viewModel = LogDetailsViewModel(httpRequest: try capture(url: uniqueURL(), stubbed: true))
        await viewModel.onFirstAppear()
        XCTAssertFalse(viewModel.canReplay, "an override would simply synthesise the same response again")
    }

    func testReplayIsNotOfferedWithoutAURL() async {
        let viewModel = LogDetailsViewModel(httpRequest: HTTPRequest())
        await viewModel.onFirstAppear()
        XCTAssertFalse(viewModel.canReplay)
    }

    func testReplayIsOfferedForARequestThatNeverAnswered() async {
        let request = HTTPRequest()
        request.requestURL = uniqueURL()
        request.requestMethod = "GET"
        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()
        XCTAssertTrue(viewModel.canReplay, "a request that timed out is exactly the one worth resending")
    }

    func testTheOriginalListsItsReplaysAndTheReplayLinksBack() async throws {
        let url = uniqueURL()
        let original = try capture(url: url)
        let replay = try capture(url: url, replayOf: original.getRandomHash() as String)
        await NetworkLogger.instance.add(original)
        await NetworkLogger.instance.add(replay)

        let originalViewModel = LogDetailsViewModel(httpRequest: original)
        await originalViewModel.loadRelatedRequests()
        XCTAssertEqual(originalViewModel.replayLinks.count, 1)
        XCTAssertTrue(originalViewModel.replayLinks.first?.replay === replay)
        XCTAssertFalse(originalViewModel.isReplay)
        XCTAssertNil(originalViewModel.originalRequest)

        let replayViewModel = LogDetailsViewModel(httpRequest: replay)
        await replayViewModel.loadRelatedRequests()
        XCTAssertTrue(replayViewModel.isReplay)
        XCTAssertTrue(replayViewModel.originalRequest === original)
        XCTAssertEqual(replayViewModel.originalSummary, "GET 200")
        XCTAssertTrue(replayViewModel.replayLinks.isEmpty)
    }

    func testAReplayWhoseOriginalHasGoneSaysSo() async throws {
        let replay = try capture(url: uniqueURL(), replayOf: "hash-that-was-never-logged")
        await NetworkLogger.instance.add(replay)

        let viewModel = LogDetailsViewModel(httpRequest: replay)
        await viewModel.loadRelatedRequests()

        XCTAssertTrue(viewModel.isReplay)
        XCTAssertNil(viewModel.originalRequest)
        XCTAssertEqual(viewModel.originalSummary, localized("No longer in the log"))
    }

    func testAnOrdinaryRequestHasNoReplaySections() async throws {
        let request = try capture(url: uniqueURL())
        await NetworkLogger.instance.add(request)

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.loadRelatedRequests()

        XCTAssertFalse(viewModel.isReplay)
        XCTAssertTrue(viewModel.replayLinks.isEmpty)
    }

    func testAReplaySentAfterThePageOpenedIsPickedUp() async throws {
        let url = uniqueURL()
        let original = try capture(url: url)
        await NetworkLogger.instance.add(original)

        let viewModel = LogDetailsViewModel(httpRequest: original)
        await viewModel.loadRelatedRequests()
        XCTAssertTrue(viewModel.replayLinks.isEmpty)

        let replay = try capture(url: url, replayOf: original.getRandomHash() as String)
        await NetworkLogger.instance.add(replay)
        await viewModel.loadRelatedRequests()

        XCTAssertEqual(viewModel.replayLinks.count, 1, "the section reflects the log, not what it held when it opened")
    }
}
