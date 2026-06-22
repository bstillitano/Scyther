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
