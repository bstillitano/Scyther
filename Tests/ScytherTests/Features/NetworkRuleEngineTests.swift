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

final class NetworkRuleEngineTests: XCTestCase {

    private func request(_ url: String = "https://api.example.com/v1/users", method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        return request
    }

    private func rule(
        _ name: String,
        enabled: Bool = true,
        path: String? = nil,
        action: NetworkRuleAction
    ) -> NetworkRule {
        NetworkRule(
            id: UUID(),
            name: name,
            isEnabled: enabled,
            match: NetworkRuleMatch(
                methods: [],
                host: nil,
                path: path.map { NetworkRulePattern(kind: .wildcard, value: $0) },
                query: [:]
            ),
            action: action
        )
    }

    private var anyMock: NetworkRuleAction {
        .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
    }

    func testNoRulesProducesAnEmptyOutcome() {
        XCTAssertEqual(NetworkRuleEngine.outcome(for: request(), rules: []), .empty)
    }

    func testDisabledRulesAreSkipped() {
        let rules = [rule("off", enabled: false, action: anyMock)]
        XCTAssertEqual(NetworkRuleEngine.outcome(for: request(), rules: rules), .empty)
    }

    func testNonMatchingRulesAreSkipped() {
        let rules = [rule("other", path: "/v2/*", action: anyMock)]
        XCTAssertEqual(NetworkRuleEngine.outcome(for: request(), rules: rules), .empty)
    }

    func testFirstMatchingStubWinsAndShortCircuits() {
        let first = MockResponse(statusCode: 201, headers: [:], bodyID: nil, delay: 0)
        let second = MockResponse(statusCode: 500, headers: [:], bodyID: nil, delay: 0)
        let rules = [rule("first", action: .mock(first)), rule("second", action: .mock(second))]
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: rules)
        XCTAssertEqual(outcome.stub, .mock(first))
        XCTAssertEqual(outcome.stubRuleName, "first")
    }

    func testFirstMatchingConditionWins() {
        let slow = NetworkCondition(latency: 5, bandwidthKBps: nil, failureRate: 0, failureCode: -1009)
        let slower = NetworkCondition(latency: 10, bandwidthKBps: nil, failureRate: 0, failureCode: -1009)
        let rules = [rule("slow", action: .condition(slow)), rule("slower", action: .condition(slower))]
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: rules)
        XCTAssertEqual(outcome.condition, slow)
        XCTAssertEqual(outcome.networkRuleNames, ["slow"])
    }

    func testEveryMatchingHeaderRewriteApplies() {
        let rules = [
            rule("a", action: .rewriteHeaders(NetworkHeaderRewrite(set: ["A": "1", "Shared": "first"], remove: []))),
            rule("b", action: .rewriteHeaders(NetworkHeaderRewrite(set: ["B": "2", "Shared": "second"], remove: ["Drop"]))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertEqual(rewrite?.set["A"], "1")
        XCTAssertEqual(rewrite?.set["B"], "2")
        XCTAssertEqual(rewrite?.set["Shared"], "second", "the later rule wins a key collision")
        XCTAssertEqual(rewrite?.remove, ["Drop"])
    }

    func testActionsOfDifferentKindsCompose() {
        let condition = NetworkCondition(latency: 1, bandwidthKBps: nil, failureRate: 0, failureCode: -1009)
        let rules = [
            rule("headers", action: .rewriteHeaders(NetworkHeaderRewrite(set: ["A": "1"], remove: []))),
            rule("condition", action: .condition(condition)),
            rule("mock", action: anyMock),
        ]
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: rules)
        XCTAssertEqual(outcome.headerRewrite?.set["A"], "1")
        XCTAssertEqual(outcome.condition, condition)
        XCTAssertNotNil(outcome.stub)
        XCTAssertEqual(
            outcome.stubRuleName,
            "mock",
            "a served stub is the only override that shaped the request"
        )
        XCTAssertEqual(
            outcome.networkRuleNames,
            ["headers", "condition"],
            "the rewrite and the condition are only credited when the request actually goes out"
        )
    }

    func testMapLocalIsAlsoAStub() {
        let file = MapLocalFile(relativePath: "fixtures/users.json", statusCode: 200, contentType: "application/json", delay: 0)
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [rule("file", action: .mapLocal(file))])
        XCTAssertEqual(outcome.stub, .mapLocal(file))
    }

    func testAKeySetByOneRuleAndRemovedByAnotherAppearsInBoth() {
        let rules = [
            rule("sets", action: .rewriteHeaders(NetworkHeaderRewrite(set: ["Authorization": "Bearer test"], remove: []))),
            rule("removes", action: .rewriteHeaders(NetworkHeaderRewrite(set: [:], remove: ["Authorization"]))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertEqual(rewrite?.set["Authorization"], "Bearer test")
        XCTAssertEqual(rewrite?.remove, ["Authorization"])
    }

    func testAKeyRemovedByOneRuleAndSetByAnotherAlsoAppearsInBoth() {
        let rules = [
            rule("removes", action: .rewriteHeaders(NetworkHeaderRewrite(set: [:], remove: ["Authorization"]))),
            rule("sets", action: .rewriteHeaders(NetworkHeaderRewrite(set: ["Authorization": "Bearer test"], remove: []))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertEqual(rewrite?.set["Authorization"], "Bearer test")
        XCTAssertEqual(rewrite?.remove, ["Authorization"], "order of the rules does not change the outcome shape")
    }
}
