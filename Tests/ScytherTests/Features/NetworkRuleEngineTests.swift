//
//  NetworkRuleEngineTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkRulePatternTests: XCTestCase {

    func testExactIsCaseInsensitiveAndWholeString() {
        let pattern = NetworkRulePattern(kind: .exact, value: "api.example.com")
        XCTAssertTrue(pattern.matches("api.example.com"))
        XCTAssertTrue(pattern.matches("API.Example.com"))
        XCTAssertFalse(pattern.matches("cdn.api.example.com"))
    }

    func testContainsMatchesAnywhere() {
        let pattern = NetworkRulePattern(kind: .contains, value: "example")
        XCTAssertTrue(pattern.matches("api.example.com"))
        XCTAssertFalse(pattern.matches("api.other.com"))
    }

    func testWildcardMatchesRuns() {
        XCTAssertTrue(NetworkRulePattern(kind: .wildcard, value: "*.example.com").matches("api.example.com"))
        XCTAssertTrue(NetworkRulePattern(kind: .wildcard, value: "/v1/*").matches("/v1/users/1"))
        XCTAssertTrue(NetworkRulePattern(kind: .wildcard, value: "/v1/*/edit").matches("/v1/users/edit"))
        XCTAssertFalse(NetworkRulePattern(kind: .wildcard, value: "/v1/*").matches("/v2/users"))
    }

    func testWildcardTreatsRegexCharactersLiterally() {
        XCTAssertTrue(NetworkRulePattern(kind: .wildcard, value: "/a+b").matches("/a+b"))
        XCTAssertFalse(NetworkRulePattern(kind: .wildcard, value: "/a+b").matches("/aab"))
    }

    func testEmptyWildcardMatchesEverything() {
        XCTAssertTrue(NetworkRulePattern(kind: .wildcard, value: "*").matches("anything"))
    }
}

final class NetworkRuleMatchTests: XCTestCase {

    private func request(_ url: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        return request
    }

    func testEmptyMatchMatchesEverything() {
        let match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: [:])
        XCTAssertTrue(match.matches(request("https://api.example.com/v1/users")))
    }

    func testMethodIsCaseInsensitive() {
        let match = NetworkRuleMatch(methods: ["POST"], host: nil, path: nil, query: [:])
        XCTAssertTrue(match.matches(request("https://a.com", method: "post")))
        XCTAssertFalse(match.matches(request("https://a.com", method: "GET")))
    }

    func testHostAndPathMustBothMatch() {
        let match = NetworkRuleMatch(
            methods: [],
            host: NetworkRulePattern(kind: .wildcard, value: "*.example.com"),
            path: NetworkRulePattern(kind: .wildcard, value: "/v1/*"),
            query: [:]
        )
        XCTAssertTrue(match.matches(request("https://api.example.com/v1/users")))
        XCTAssertFalse(match.matches(request("https://api.example.com/v2/users")))
        XCTAssertFalse(match.matches(request("https://api.other.com/v1/users")))
    }

    func testQueryIsASubsetTest() {
        let match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: ["page": "2"])
        XCTAssertTrue(match.matches(request("https://a.com/x?page=2&sort=name")))
        XCTAssertFalse(match.matches(request("https://a.com/x?page=3")))
        XCTAssertFalse(match.matches(request("https://a.com/x")))
    }

    func testMatchIgnoresPortAndScheme() {
        let match = NetworkRuleMatch(
            methods: [],
            host: NetworkRulePattern(kind: .exact, value: "localhost"),
            path: nil,
            query: [:]
        )
        XCTAssertTrue(match.matches(request("http://localhost:8080/health")))
    }

    func testAMethodOnlyMatchStillMatchesWhenTheURLIsMissing() {
        var request = URLRequest(url: URL(string: "https://a.com")!)
        request.httpMethod = "POST"
        request.url = nil
        let match = NetworkRuleMatch(methods: ["POST"], host: nil, path: nil, query: [:])
        XCTAssertTrue(match.matches(request), "every non-empty facet is satisfied, so the match holds")
    }

    func testAHostMatchCannotMatchWhenTheURLIsMissing() {
        var request = URLRequest(url: URL(string: "https://a.com")!)
        request.httpMethod = "GET"
        request.url = nil
        let match = NetworkRuleMatch(
            methods: [],
            host: NetworkRulePattern(kind: .exact, value: "a.com"),
            path: nil,
            query: [:]
        )
        XCTAssertFalse(match.matches(request), "a host constraint cannot be satisfied without a URL")
    }
}
