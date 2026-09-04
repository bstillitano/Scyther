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
