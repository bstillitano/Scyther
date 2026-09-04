//
//  NetworkLogFilterTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkLogFilterTests: XCTestCase {

    private func makeRequest(
        method: String? = "GET",
        url: String? = "https://api.example.com/users",
        code: Int? = 200,
        shortType: HTTPModelShortType = .JSON
    ) -> HTTPRequest {
        let request = HTTPRequest()
        request.requestMethod = method
        request.requestURL = url
        request.responseCode = code
        request.noResponse = code == nil
        request.shortType = shortType.rawValue
        return request
    }

    // MARK: - Empty filter

    func testEmptyFilterIsInactiveAndMatchesEverything() {
        let filter = NetworkLogFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertTrue(filter.matches(makeRequest()))
        XCTAssertTrue(filter.matches(makeRequest(method: nil, url: nil, code: nil, shortType: .OTHER)))
    }

    // MARK: - Method

    func testMethodFilterMatchesCaseInsensitively() {
        var filter = NetworkLogFilter()
        filter.methods = ["POST"]
        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.matches(makeRequest(method: "post")))
        XCTAssertFalse(filter.matches(makeRequest(method: "GET")))
        XCTAssertFalse(filter.matches(makeRequest(method: nil)))
    }

    func testMethodFilterAllowsMultipleValues() {
        var filter = NetworkLogFilter()
        filter.methods = ["GET", "DELETE"]
        XCTAssertTrue(filter.matches(makeRequest(method: "GET")))
        XCTAssertTrue(filter.matches(makeRequest(method: "DELETE")))
        XCTAssertFalse(filter.matches(makeRequest(method: "PUT")))
    }

    // MARK: - Status

    func testStatusClassIsDerivedFromResponseCode() {
        XCTAssertEqual(HTTPStatusClass(request: makeRequest(code: 200)), .success)
        XCTAssertEqual(HTTPStatusClass(request: makeRequest(code: 204)), .success)
        XCTAssertEqual(HTTPStatusClass(request: makeRequest(code: 301)), .redirect)
        XCTAssertEqual(HTTPStatusClass(request: makeRequest(code: 404)), .clientError)
        XCTAssertEqual(HTTPStatusClass(request: makeRequest(code: 503)), .serverError)
        XCTAssertEqual(HTTPStatusClass(request: makeRequest(code: nil)), .pending)
        XCTAssertEqual(HTTPStatusClass(request: makeRequest(code: 0)), .pending)
    }

    func testStatusFilterMatchesByClass() {
        var filter = NetworkLogFilter()
        filter.statusClasses = [.clientError, .pending]
        XCTAssertTrue(filter.matches(makeRequest(code: 401)))
        XCTAssertTrue(filter.matches(makeRequest(code: nil)))
        XCTAssertFalse(filter.matches(makeRequest(code: 200)))
        XCTAssertFalse(filter.matches(makeRequest(code: 500)))
    }

    // MARK: - Host

    func testHostIsDerivedFromRequestURL() {
        XCTAssertEqual(makeRequest(url: "https://API.Example.com/users?id=1").host, "api.example.com")
        XCTAssertNil(makeRequest(url: nil).host)
        XCTAssertNil(makeRequest(url: "not a url").host)
    }

    func testHostFilterMatchesCaseInsensitively() {
        var filter = NetworkLogFilter()
        filter.hosts = ["api.example.com"]
        XCTAssertTrue(filter.matches(makeRequest(url: "https://API.example.com/a")))
        XCTAssertFalse(filter.matches(makeRequest(url: "https://cdn.example.com/a")))
        XCTAssertFalse(filter.matches(makeRequest(url: nil)))
    }

    func testHostExcludeModeInvertsMatching() {
        var filter = NetworkLogFilter()
        filter.hosts = ["api.example.com"]
        filter.hostMode = .exclude
        XCTAssertTrue(filter.isActive)
        XCTAssertFalse(filter.matches(makeRequest(url: "https://api.example.com/a")))
        XCTAssertTrue(filter.matches(makeRequest(url: "https://cdn.example.com/a")))
        XCTAssertTrue(filter.matches(makeRequest(url: nil)))
    }

    func testHostModeAloneDoesNotActivateFilterAndClearResetsIt() {
        var filter = NetworkLogFilter()
        filter.hostMode = .exclude
        XCTAssertFalse(filter.isActive)
        XCTAssertTrue(filter.matches(makeRequest()))
        filter.hosts = ["a.com"]
        filter.clear()
        XCTAssertEqual(filter.hostMode, .include)
    }

    // MARK: - Content type

    func testContentTypeFilterMatchesShortType() {
        var filter = NetworkLogFilter()
        filter.contentTypes = [.IMAGE, .HTML]
        XCTAssertTrue(filter.matches(makeRequest(shortType: .IMAGE)))
        XCTAssertTrue(filter.matches(makeRequest(shortType: .HTML)))
        XCTAssertFalse(filter.matches(makeRequest(shortType: .JSON)))
    }

    // MARK: - Combination

    func testDimensionsCombineWithAnd() {
        var filter = NetworkLogFilter()
        filter.methods = ["GET"]
        filter.statusClasses = [.success]
        filter.hosts = ["api.example.com"]
        filter.contentTypes = [.JSON]

        XCTAssertTrue(filter.matches(makeRequest()))
        XCTAssertFalse(filter.matches(makeRequest(method: "POST")))
        XCTAssertFalse(filter.matches(makeRequest(code: 500)))
        XCTAssertFalse(filter.matches(makeRequest(url: "https://other.com/x")))
        XCTAssertFalse(filter.matches(makeRequest(shortType: .XML)))
    }

    func testSelectionCountPerDimension() {
        var filter = NetworkLogFilter()
        filter.methods = ["GET", "POST"]
        filter.hosts = ["a.com"]
        XCTAssertEqual(filter.selectionCount(for: .method), 2)
        XCTAssertEqual(filter.selectionCount(for: .status), 0)
        XCTAssertEqual(filter.selectionCount(for: .host), 1)
        XCTAssertEqual(filter.selectionCount(for: .contentType), 0)
    }

    func testClearRemovesAllSelections() {
        var filter = NetworkLogFilter()
        filter.methods = ["GET"]
        filter.statusClasses = [.success]
        filter.hosts = ["a.com"]
        filter.contentTypes = [.JSON]
        filter.clear()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter, NetworkLogFilter())
    }

    func testSelectionsAreReadAndWrittenByDimension() {
        var filter = NetworkLogFilter()
        filter.setSelection(["GET"], for: .method)
        filter.setSelection([HTTPStatusClass.success.rawValue], for: .status)
        filter.setSelection(["a.com"], for: .host)
        filter.setSelection([HTTPModelShortType.XML.rawValue], for: .contentType)

        XCTAssertEqual(filter.methods, ["GET"])
        XCTAssertEqual(filter.statusClasses, [.success])
        XCTAssertEqual(filter.hosts, ["a.com"])
        XCTAssertEqual(filter.contentTypes, [.XML])

        XCTAssertEqual(filter.selection(for: .method), ["GET"])
        XCTAssertEqual(filter.selection(for: .status), [HTTPStatusClass.success.rawValue])
        XCTAssertEqual(filter.selection(for: .host), ["a.com"])
        XCTAssertEqual(filter.selection(for: .contentType), [HTTPModelShortType.XML.rawValue])
    }
}

// MARK: - Extended dimensions

final class NetworkLogFilterExtendedTests: XCTestCase {

    private func makeRequest(
        isGraphQL: Bool = false,
        operationType: GraphQLOperationType? = nil,
        durationMs: Float? = 50,
        code: Int? = 200,
        date: Date? = Date()
    ) -> HTTPRequest {
        let request = HTTPRequest()
        request.requestMethod = "GET"
        request.requestURL = "https://api.example.com/x"
        request.isGraphQL = isGraphQL
        request.graphQLOperationType = operationType
        request.requestDuration = durationMs
        request.responseCode = code
        request.noResponse = code == nil
        request.requestDate = date
        return request
    }

    // MARK: API kind

    func testAPIKindIsDerivedFromRequest() {
        XCTAssertEqual(APIKind(request: makeRequest()), .rest)
        XCTAssertEqual(APIKind(request: makeRequest(isGraphQL: true, operationType: .query)), .graphQL)
        XCTAssertEqual(APIKind(request: makeRequest(isGraphQL: true, operationType: nil)), .graphQL)
    }

    func testAPIFilterMatchesByKind() {
        var filter = NetworkLogFilter()
        filter.apiKinds = [.graphQL]
        XCTAssertTrue(filter.matches(makeRequest(isGraphQL: true, operationType: .query)))
        XCTAssertFalse(filter.matches(makeRequest()))
        filter.apiKinds = [.rest]
        XCTAssertTrue(filter.matches(makeRequest()))
        XCTAssertFalse(filter.matches(makeRequest(isGraphQL: true, operationType: nil)))
    }

    // MARK: GraphQL operation

    func testGraphQLOperationIsDerivedFromRequest() {
        XCTAssertNil(GraphQLOperationFilter(request: makeRequest()))
        XCTAssertEqual(GraphQLOperationFilter(request: makeRequest(isGraphQL: true, operationType: .query)), .query)
        XCTAssertEqual(GraphQLOperationFilter(request: makeRequest(isGraphQL: true, operationType: .mutation)), .mutation)
        XCTAssertEqual(GraphQLOperationFilter(request: makeRequest(isGraphQL: true, operationType: .subscription)), .subscription)
        XCTAssertEqual(GraphQLOperationFilter(request: makeRequest(isGraphQL: true, operationType: nil)), .batch)
    }

    func testGraphQLFilterMatchesOperationAndExcludesREST() {
        var filter = NetworkLogFilter()
        filter.graphQLOperations = [.mutation, .batch]
        XCTAssertTrue(filter.matches(makeRequest(isGraphQL: true, operationType: .mutation)))
        XCTAssertTrue(filter.matches(makeRequest(isGraphQL: true, operationType: nil)))
        XCTAssertFalse(filter.matches(makeRequest(isGraphQL: true, operationType: .query)))
        XCTAssertFalse(filter.matches(makeRequest()))
    }

    // MARK: Duration

    func testDurationBucketIsDerivedFromMilliseconds() {
        XCTAssertEqual(DurationBucket(request: makeRequest(durationMs: 0)), .under100ms)
        XCTAssertEqual(DurationBucket(request: makeRequest(durationMs: 99.9)), .under100ms)
        XCTAssertEqual(DurationBucket(request: makeRequest(durationMs: 100)), .from100msTo500ms)
        XCTAssertEqual(DurationBucket(request: makeRequest(durationMs: 500)), .from500msTo1s)
        XCTAssertEqual(DurationBucket(request: makeRequest(durationMs: 1000)), .from1sTo3s)
        XCTAssertEqual(DurationBucket(request: makeRequest(durationMs: 3000)), .over3s)
        XCTAssertNil(DurationBucket(request: makeRequest(durationMs: nil)))
    }

    func testDurationFilterMatchesBucketAndExcludesPending() {
        var filter = NetworkLogFilter()
        filter.durationBuckets = [.over3s, .from1sTo3s]
        XCTAssertTrue(filter.matches(makeRequest(durationMs: 4500)))
        XCTAssertTrue(filter.matches(makeRequest(durationMs: 1500)))
        XCTAssertFalse(filter.matches(makeRequest(durationMs: 20)))
        XCTAssertFalse(filter.matches(makeRequest(durationMs: nil, code: nil)))
    }

    // MARK: Exact status code

    func testStatusCodeFilterMatchesExactCode() {
        var filter = NetworkLogFilter()
        filter.statusCodes = [404, 201]
        XCTAssertTrue(filter.matches(makeRequest(code: 404)))
        XCTAssertTrue(filter.matches(makeRequest(code: 201)))
        XCTAssertFalse(filter.matches(makeRequest(code: 200)))
        XCTAssertFalse(filter.matches(makeRequest(code: nil)))
    }

    // MARK: Recency

    func testRecencyWindowMatchesAgainstInjectedNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var filter = NetworkLogFilter()
        filter.recencyWindow = .lastFiveMinutes

        XCTAssertTrue(filter.matches(makeRequest(date: now.addingTimeInterval(-299)), now: now))
        XCTAssertFalse(filter.matches(makeRequest(date: now.addingTimeInterval(-301)), now: now))
        XCTAssertFalse(filter.matches(makeRequest(date: nil), now: now))
    }

    func testRecencyIsSingleSelectAndSetSelectionKeepsWidestWindow() {
        XCTAssertTrue(NetworkLogFilterDimension.recency.isSingleSelect)
        XCTAssertFalse(NetworkLogFilterDimension.method.isSingleSelect)

        var filter = NetworkLogFilter()
        filter.setSelection([RecencyWindow.lastMinute.rawValue, RecencyWindow.lastHour.rawValue], for: .recency)
        XCTAssertEqual(filter.recencyWindow, .lastHour)
        XCTAssertEqual(filter.selectionCount(for: .recency), 1)
    }

    // MARK: Dimension plumbing

    func testNewDimensionsRoundTripThroughSelectionAPI() {
        var filter = NetworkLogFilter()
        filter.setSelection([APIKind.graphQL.rawValue], for: .api)
        filter.setSelection([GraphQLOperationFilter.query.rawValue], for: .graphQL)
        filter.setSelection([DurationBucket.over3s.rawValue], for: .duration)
        filter.setSelection(["404", "500", "not-a-code"], for: .statusCode)
        filter.setSelection([RecencyWindow.lastMinute.rawValue], for: .recency)

        XCTAssertEqual(filter.apiKinds, [.graphQL])
        XCTAssertEqual(filter.graphQLOperations, [.query])
        XCTAssertEqual(filter.durationBuckets, [.over3s])
        XCTAssertEqual(filter.statusCodes, [404, 500])
        XCTAssertEqual(filter.recencyWindow, .lastMinute)

        XCTAssertEqual(filter.selection(for: .api), ["graphQL"])
        XCTAssertEqual(filter.selection(for: .graphQL), ["query"])
        XCTAssertEqual(filter.selection(for: .duration), [DurationBucket.over3s.rawValue])
        XCTAssertEqual(filter.selection(for: .statusCode), ["404", "500"])
        XCTAssertEqual(filter.selection(for: .recency), [RecencyWindow.lastMinute.rawValue])
        XCTAssertEqual(filter.totalSelectionCount, 6)
        XCTAssertTrue(filter.isActive)

        filter.clear()
        XCTAssertEqual(filter.totalSelectionCount, 0)
    }

    func testGroupsPartitionEveryDimensionExactlyOnce() {
        let grouped = NetworkLogFilterGroup.allCases.flatMap(\.dimensions)
        XCTAssertEqual(Set(grouped), Set(NetworkLogFilterDimension.allCases))
        XCTAssertEqual(grouped.count, NetworkLogFilterDimension.allCases.count)
        for dimension in NetworkLogFilterDimension.allCases {
            XCTAssertTrue(dimension.group.dimensions.contains(dimension))
        }
    }

    func testGroupMembership() {
        XCTAssertEqual(NetworkLogFilterGroup.request.dimensions, [.method, .host, .api, .graphQL])
        XCTAssertEqual(NetworkLogFilterGroup.response.dimensions, [.status, .statusCode, .contentType])
        XCTAssertEqual(NetworkLogFilterGroup.timing.dimensions, [.duration, .recency])
    }

    func testChipHeightIsFixedAt40Points() {
        XCTAssertEqual(NetworkLogFilterChip.height, 40)
    }

    func testDimensionOrderStartsWithOriginalFour() {
        XCTAssertEqual(
            NetworkLogFilterDimension.allCases,
            [.method, .status, .host, .contentType, .api, .graphQL, .duration, .statusCode, .recency]
        )
    }
}
