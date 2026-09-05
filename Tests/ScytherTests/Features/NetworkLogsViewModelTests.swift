//
//  NetworkLogsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkLogsViewModelTests: XCTestCase {

    func testSearchMatchesOperationName() {
        let gql = HTTPRequest()
        gql.requestURL = "https://api.example.com/graphql"
        gql.requestMethod = "POST"
        gql.graphQLOperationName = "GetUserProfile"

        let rest = HTTPRequest()
        rest.requestURL = "https://api.example.com/users"
        rest.requestMethod = "GET"

        let filtered = NetworkLogsViewModel.filter(
            items: [gql, rest],
            searchTerm: "getuserprofile"
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.requestURL, "https://api.example.com/graphql")
    }

    func testEmptySearchReturnsAll() {
        let a = HTTPRequest()
        let b = HTTPRequest()
        XCTAssertEqual(NetworkLogsViewModel.filter(items: [a, b], searchTerm: "").count, 2)
    }
}

// MARK: - Filter integration

@MainActor
final class NetworkLogsViewModelFilterTests: XCTestCase {

    private func makeRequest(method: String, url: String, code: Int?) -> HTTPRequest {
        let request = HTTPRequest()
        request.requestMethod = method
        request.requestURL = url
        request.responseCode = code
        request.noResponse = code == nil
        return request
    }

    func testFilterAndSearchCompose() {
        let a = makeRequest(method: "GET", url: "https://api.example.com/users", code: 200)
        let b = makeRequest(method: "POST", url: "https://api.example.com/users", code: 201)
        let c = makeRequest(method: "GET", url: "https://api.example.com/orders", code: 200)

        var filter = NetworkLogFilter()
        filter.methods = ["GET"]

        let result = NetworkLogsViewModel.filter(items: [a, b, c], searchTerm: "users", filter: filter)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === a)
    }

    func testFilterWithEmptySearchOnlyAppliesChips() {
        let a = makeRequest(method: "GET", url: "https://api.example.com/users", code: 200)
        let b = makeRequest(method: "POST", url: "https://api.example.com/users", code: 500)

        var filter = NetworkLogFilter()
        filter.statusClasses = [.serverError]

        let result = NetworkLogsViewModel.filter(items: [a, b], searchTerm: "", filter: filter)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === b)
    }

    func testAvailableMethodsAreDistinctUppercasedAndSorted() {
        let items = [
            makeRequest(method: "post", url: "https://a.com", code: 200),
            makeRequest(method: "GET", url: "https://a.com", code: 200),
            makeRequest(method: "POST", url: "https://a.com", code: 200),
        ]
        XCTAssertEqual(NetworkLogsViewModel.availableMethods(in: items), ["GET", "POST"])
    }

    func testAvailableHostsAreDistinctLowercasedAndSorted() {
        let items = [
            makeRequest(method: "GET", url: "https://Zeta.com/x", code: 200),
            makeRequest(method: "GET", url: "https://alpha.com/y", code: 200),
            makeRequest(method: "GET", url: "https://zeta.com/z", code: 200),
            makeRequest(method: "GET", url: "-", code: nil),
        ]
        XCTAssertEqual(NetworkLogsViewModel.availableHosts(in: items), ["alpha.com", "zeta.com"])
    }

    func testOptionsForDimensionUseStaticListsForStatusAndContentType() {
        let viewModel = NetworkLogsViewModel()
        let status = viewModel.options(for: .status)
        XCTAssertEqual(status.map(\.id), HTTPStatusClass.allCases.map(\.rawValue))
        let types = viewModel.options(for: .contentType)
        XCTAssertEqual(types.map(\.id), HTTPModelShortType.allCases.map(\.rawValue))
    }
}

// MARK: - Extended options

@MainActor
final class NetworkLogsViewModelExtendedOptionsTests: XCTestCase {

    private func makeRequest(code: Int?) -> HTTPRequest {
        let request = HTTPRequest()
        request.requestMethod = "GET"
        request.requestURL = "https://a.com"
        request.responseCode = code
        request.noResponse = code == nil
        return request
    }

    func testAvailableStatusCodesAreDistinctSortedAndExcludePending() {
        let items = [makeRequest(code: 500), makeRequest(code: 200), makeRequest(code: 500), makeRequest(code: nil), makeRequest(code: 0)]
        XCTAssertEqual(NetworkLogsViewModel.availableStatusCodes(in: items), [200, 500])
    }

    func testChipTitleShowsValueForSingleSelectionAndCountForMultiple() {
        let viewModel = NetworkLogsViewModel()
        XCTAssertEqual(viewModel.chipTitle(for: .recency), "Recency")

        viewModel.filter.recencyWindow = .lastHour
        XCTAssertEqual(viewModel.chipTitle(for: .recency), "Last hour")

        viewModel.filter.statusClasses = [.success]
        XCTAssertEqual(viewModel.chipTitle(for: .status), "2xx Success")

        viewModel.filter.statusClasses = [.success, .serverError]
        XCTAssertEqual(viewModel.chipTitle(for: .status), "Status · 2")

        viewModel.filter.methods = ["GET"]
        XCTAssertEqual(viewModel.chipTitle(for: .method), "GET")
    }

    func testChipTitleMarksSingleExcludedHost() {
        let viewModel = NetworkLogsViewModel()
        viewModel.filter.hosts = ["a.com"]
        viewModel.filter.hostMode = .exclude
        XCTAssertEqual(viewModel.chipTitle(for: .host), "Not a.com")
        viewModel.filter.hostMode = .include
        XCTAssertEqual(viewModel.chipTitle(for: .host), "a.com")
    }

    func testStaticOptionsForNewDimensions() {
        let viewModel = NetworkLogsViewModel()
        XCTAssertEqual(viewModel.options(for: .api).map(\.id), APIKind.allCases.map(\.rawValue))
        XCTAssertEqual(viewModel.options(for: .graphQL).map(\.id), GraphQLOperationFilter.allCases.map(\.rawValue))
        XCTAssertEqual(viewModel.options(for: .duration).map(\.id), DurationBucket.allCases.map(\.rawValue))
        XCTAssertEqual(viewModel.options(for: .recency).map(\.id), RecencyWindow.allCases.map(\.rawValue))
        XCTAssertEqual(viewModel.options(for: .statusCode), [])
    }
}

// MARK: - Replay lookups

@MainActor
final class NetworkLogsViewModelReplayLookupTests: XCTestCase {

    private func request(replayOf id: String? = nil) -> HTTPRequest {
        let request = HTTPRequest()
        request.requestURL = "https://api.example.com/v1/users"
        request.requestMethod = "GET"
        request.replayOfID = id
        return request
    }

    func testReplaysAreThoseCarryingTheOriginalsHash() {
        let original = request()
        let hash = original.getRandomHash() as String
        let mine = request(replayOf: hash)
        let somebodyElses = request(replayOf: "other-hash")
        let ordinary = request()

        let found = NetworkLogsViewModel.replays(of: original, in: [mine, somebodyElses, ordinary])
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found.first === mine)
    }

    func testReplaysKeepTheOrderTheLogGaveThem() {
        let original = request()
        let hash = original.getRandomHash() as String
        let newest = request(replayOf: hash)
        let oldest = request(replayOf: hash)

        let found = NetworkLogsViewModel.replays(of: original, in: [newest, request(), oldest])
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found[0] === newest)
        XCTAssertTrue(found[1] === oldest)
    }

    func testARequestWithNoReplaysFindsNone() {
        let original = request()
        XCTAssertTrue(NetworkLogsViewModel.replays(of: original, in: [request(), request()]).isEmpty)
    }

    func testTheOriginalIsFoundByHash() {
        let original = request()
        let replay = request(replayOf: original.getRandomHash() as String)
        let found = NetworkLogsViewModel.original(of: replay, in: [request(), original])
        XCTAssertTrue(found === original)
    }

    func testAnOrdinaryRequestHasNoOriginal() {
        XCTAssertNil(NetworkLogsViewModel.original(of: request(), in: [request()]))
    }

    func testAReplayWhoseOriginalHasBeenClearedFindsNothing() {
        let replay = request(replayOf: "vanished-hash")
        XCTAssertNil(NetworkLogsViewModel.original(of: replay, in: [request(), request()]))
    }

    func testAReplayOfAReplayListsUnderTheRequestItWasBuiltFrom() {
        let first = request()
        let second = request(replayOf: first.getRandomHash() as String)
        let third = request(replayOf: second.getRandomHash() as String)
        let items = [third, second, first]

        XCTAssertEqual(NetworkLogsViewModel.replays(of: first, in: items).count, 1)
        XCTAssertTrue(NetworkLogsViewModel.replays(of: first, in: items).first === second)
        XCTAssertTrue(NetworkLogsViewModel.replays(of: second, in: items).first === third)
    }
}

// MARK: - Replay rows

@MainActor
final class ReplayLinkTests: XCTestCase {

    private func request(method: String = "GET", status: Int?, duration: Float?, size: Int?) -> HTTPRequest {
        let request = HTTPRequest()
        request.requestMethod = method
        request.responseCode = status
        request.requestDuration = duration
        request.responseBodyLength = size
        return request
    }

    func testARowNamesTheMethodAndStatusAndSignsBothDeltas() {
        let original = request(status: 200, duration: 100, size: 500)
        let replay = request(method: "POST", status: 401, duration: 124, size: 40)
        let link = ReplayLink(replay: replay, original: original)

        XCTAssertEqual(link.title, "POST 401")
        XCTAssertEqual(link.detail, "+24 ms · -460 B")
        XCTAssertTrue(link.comparison.statusChanged)
    }

    func testAnIdenticalReplayStillSignsItsZeroes() {
        let original = request(status: 200, duration: 100, size: 500)
        let link = ReplayLink(replay: request(status: 200, duration: 100, size: 500), original: original)
        XCTAssertEqual(link.title, "GET 200")
        XCTAssertEqual(link.detail, "+0 ms · +0 B")
    }

    func testAFailedReplayIsNamedAndCarriesNoDeltas() {
        let original = request(status: 200, duration: 100, size: 500)
        let link = ReplayLink(replay: request(status: nil, duration: nil, size: nil), original: original)
        XCTAssertEqual(link.title, "GET \(localized("Failed"))")
        XCTAssertEqual(link.detail, "")
    }

    func testEachRowHasItsOwnIdentity() {
        let original = request(status: 200, duration: 100, size: 500)
        let first = ReplayLink(replay: request(status: 200, duration: 100, size: 500), original: original)
        let second = ReplayLink(replay: request(status: 200, duration: 100, size: 500), original: original)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testSummaryDescribesARequest() {
        XCTAssertEqual(LogDetailsViewModel.summary(of: request(method: "PATCH", status: 204, duration: 1, size: 0)),
                       "PATCH 204")
        let unknown = HTTPRequest()
        XCTAssertEqual(LogDetailsViewModel.summary(of: unknown), "- \(localized("Failed"))")
    }
}
