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

    /// "Anywhere" means anywhere: a substring at the very start and one at the very end both
    /// count. Asserting only the middle would pass just as well against a `hasPrefix` or a
    /// `hasSuffix` implementation, neither of which is what the kind is named for.
    func testContainsMatchesAnywhere() {
        let pattern = NetworkRulePattern(kind: .contains, value: "example")
        XCTAssertTrue(pattern.matches("example.com"), "a match at the very start counts")
        XCTAssertTrue(pattern.matches("api.example.com"), "a match in the middle counts")
        XCTAssertTrue(pattern.matches("api.example"), "a match at the very end counts")
        XCTAssertTrue(pattern.matches("example"), "the whole candidate counts")
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

    /// The star matches everything. The test that used to carry this assertion was called
    /// `testEmptyWildcardMatchesEverything`, which named a different — and untrue — claim: an
    /// *empty* wildcard is an empty string, and as a comparison it matches only the empty string.
    /// What an empty pattern means to a rule is settled by ``NetworkRuleMatch``, not here.
    func testStarWildcardMatchesEverything() {
        XCTAssertTrue(NetworkRulePattern(kind: .wildcard, value: "*").matches("anything"))
        XCTAssertTrue(NetworkRulePattern(kind: .wildcard, value: "*").matches(""))
    }

    /// A pattern is a comparison and nothing more, so an empty one compares as an empty string.
    /// ``NetworkRuleMatch`` is where an empty pattern is read as "no constraint".
    func testAnEmptyPatternValueMatchesOnlyTheEmptyString() {
        let empty = NetworkRulePattern(kind: .wildcard, value: "")
        XCTAssertFalse(empty.matches("anything"))
        XCTAssertTrue(empty.matches(""))
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

    /// The host facet is compared against the host alone, so neither the scheme nor the port is
    /// part of it — and a pattern that spells the port out cannot match, which is the half that
    /// proves the port is genuinely absent rather than merely tolerated.
    func testMatchIgnoresPortAndScheme() {
        let match = NetworkRuleMatch(
            methods: [],
            host: NetworkRulePattern(kind: .exact, value: "localhost"),
            path: nil,
            query: [:]
        )
        XCTAssertTrue(match.matches(request("http://localhost:8080/health")))
        XCTAssertTrue(match.matches(request("https://localhost/health")))

        let withPort = NetworkRuleMatch(
            methods: [],
            host: NetworkRulePattern(kind: .exact, value: "localhost:8080"),
            path: nil,
            query: [:]
        )
        XCTAssertFalse(withPort.matches(request("http://localhost:8080/health")),
                       "the port is not part of the host a pattern is compared against")
    }

    // MARK: - Path

    /// A URL with no path at all — `https://api.example.com` — presents as `"/"`, which is what
    /// both producers of a rule write into the pattern. Comparing the raw empty string here made
    /// every such override dead on arrival.
    func testAnEmptyPathIsNormalisedToRoot() {
        let match = NetworkRuleMatch(
            methods: [],
            host: nil,
            path: NetworkRulePattern(kind: .exact, value: "/"),
            query: [:]
        )
        XCTAssertTrue(match.matches(request("https://api.example.com")))
        XCTAssertTrue(match.matches(request("https://api.example.com/")))
    }

    /// A trailing slash is a different path, and an exact pattern says so.
    func testATrailingSlashIsPartOfThePath() {
        let match = NetworkRuleMatch(
            methods: [],
            host: nil,
            path: NetworkRulePattern(kind: .exact, value: "/v1/users"),
            query: [:]
        )
        XCTAssertTrue(match.matches(request("https://a.com/v1/users")))
        XCTAssertFalse(match.matches(request("https://a.com/v1/users/")),
                       "an exact path pattern does not ignore a trailing slash")
    }

    /// The path is compared exactly as it travels on the wire. An escaped separator is not a
    /// separator, so `/v1/a%2Fb` is one segment and must not satisfy a rule written for the two
    /// segments `/v1/a/b`.
    func testPathIsMatchedBeforePercentDecoding() {
        let match = NetworkRuleMatch(
            methods: [],
            host: nil,
            path: NetworkRulePattern(kind: .exact, value: "/v1/a/b"),
            query: [:]
        )
        XCTAssertTrue(match.matches(request("https://a.com/v1/a/b")))
        XCTAssertFalse(match.matches(request("https://a.com/v1/a%2Fb")),
                       "an escaped separator is not a separator")
    }

    /// The corollary: a path copied out of the log, out of a HAR, or off the address bar is
    /// percent-encoded, and pasting it into a rule has to work.
    func testAnEncodedPathMatchesTheEncodedPatternItWasCopiedFrom() {
        let match = NetworkRuleMatch(
            methods: [],
            host: nil,
            path: NetworkRulePattern(kind: .exact, value: "/v1/a%20b"),
            query: [:]
        )
        XCTAssertTrue(match.matches(request("https://a.com/v1/a%20b")))
    }

    // MARK: - Empty facets

    /// A pattern with an empty value places no constraint, as ``NetworkRuleMatch``'s own
    /// documentation promises. Comparing it as a string instead made it constrain everything
    /// away: the empty host equalled no host at all, so the rule could never fire.
    func testAPatternWithAnEmptyValuePlacesNoConstraint() {
        let match = NetworkRuleMatch(
            methods: [],
            host: NetworkRulePattern(kind: .exact, value: ""),
            path: NetworkRulePattern(kind: .wildcard, value: ""),
            query: [:]
        )
        XCTAssertTrue(match.matches(request("https://api.example.com/v1/users")))
    }

    /// And an empty pattern cannot fail a request with no URL either, since it constrains nothing.
    func testAnEmptyPatternStillMatchesWhenTheURLIsMissing() {
        var request = URLRequest(url: URL(string: "https://a.com")!)
        request.httpMethod = "GET"
        request.url = nil
        let match = NetworkRuleMatch(
            methods: [],
            host: NetworkRulePattern(kind: .exact, value: ""),
            path: nil,
            query: [:]
        )
        XCTAssertTrue(match.matches(request))
    }

    // MARK: - Query

    /// A repeated key is matched against every occurrence, not just the first. A rule asking for
    /// `page=2` against `?page=1&page=2` is asking whether that pair is present, and it is.
    func testARepeatedQueryKeyMatchesAnyOccurrence() {
        let match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: ["page": "2"])
        XCTAssertTrue(match.matches(request("https://a.com/x?page=1&page=2")))
        XCTAssertTrue(match.matches(request("https://a.com/x?page=2&page=1")))
        XCTAssertFalse(match.matches(request("https://a.com/x?page=1&page=3")))
    }

    /// A key present with no value at all reads as an empty value, so `?flag` and `?flag=` both
    /// satisfy a rule written for `flag` = `""`.
    func testAValuelessQueryKeyMatchesAnEmptyExpectedValue() {
        let match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: ["flag": ""])
        XCTAssertTrue(match.matches(request("https://a.com/x?flag")))
        XCTAssertTrue(match.matches(request("https://a.com/x?flag=")))
        XCTAssertFalse(match.matches(request("https://a.com/x?flag=1")))
    }

    /// Query names are case-sensitive — unlike a header name, and unlike a host or path pattern.
    func testQueryNamesAreCaseSensitive() {
        let match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: ["Page": "2"])
        XCTAssertTrue(match.matches(request("https://a.com/x?Page=2")))
        XCTAssertFalse(match.matches(request("https://a.com/x?page=2")))
    }

    /// Query values are compared after percent-decoding, so a value with a space is written the
    /// way a developer would say it rather than the way it travels.
    func testQueryValuesAreComparedDecoded() {
        let match = NetworkRuleMatch(methods: [], host: nil, path: nil, query: ["q": "hello world"])
        XCTAssertTrue(match.matches(request("https://a.com/x?q=hello%20world")))
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
        actions: NetworkRuleActions
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
            actions: actions
        )
    }

    private var anyMock: NetworkRuleActions {
        NetworkRuleActions(stub: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0)))
    }

    func testNoRulesProducesAnEmptyOutcome() {
        XCTAssertEqual(NetworkRuleEngine.outcome(for: request(), rules: []), .empty)
    }

    func testDisabledRulesAreSkipped() {
        let rules = [rule("off", enabled: false, actions: anyMock)]
        XCTAssertEqual(NetworkRuleEngine.outcome(for: request(), rules: rules), .empty)
    }

    func testNonMatchingRulesAreSkipped() {
        let rules = [rule("other", path: "/v2/*", actions: anyMock)]
        XCTAssertEqual(NetworkRuleEngine.outcome(for: request(), rules: rules), .empty)
    }

    func testFirstMatchingStubWinsAndShortCircuits() {
        let first = MockResponse(statusCode: 201, headers: [:], bodyID: nil, delay: 0)
        let second = MockResponse(statusCode: 500, headers: [:], bodyID: nil, delay: 0)
        let rules = [rule("first", actions: NetworkRuleActions(stub: .mock(first))), rule("second", actions: NetworkRuleActions(stub: .mock(second)))]
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: rules)
        XCTAssertEqual(outcome.stub, .mock(first))
        XCTAssertEqual(outcome.stubRuleName, "first")
    }

    func testFirstMatchingConditionWins() {
        let slow = NetworkCondition(latency: 5, bandwidthKBps: nil, failureRate: 0, failureCode: -1009)
        let slower = NetworkCondition(latency: 10, bandwidthKBps: nil, failureRate: 0, failureCode: -1009)
        let rules = [rule("slow", actions: NetworkRuleActions(condition: slow)), rule("slower", actions: NetworkRuleActions(condition: slower))]
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: rules)
        XCTAssertEqual(outcome.condition, slow)
        XCTAssertEqual(outcome.networkRuleNames, ["slow"])
    }

    func testEveryMatchingHeaderRewriteApplies() {
        let rules = [
            rule("a", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["A": "1", "Shared": "first"], remove: []))),
            rule("b", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["B": "2", "Shared": "second"], remove: ["Drop"]))),
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
            rule("headers", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["A": "1"], remove: []))),
            rule("condition", actions: NetworkRuleActions(condition: condition)),
            rule("mock", actions: anyMock),
        ]
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: rules)
        XCTAssertEqual(outcome.headerRewrite?.set["A"], "1")
        XCTAssertEqual(outcome.condition, condition)
        XCTAssertNotNil(outcome.stub)
        XCTAssertEqual(
            outcome.stubRuleName,
            "mock",
            "the stub is credited separately, because that credit depends on it being producible"
        )
        XCTAssertEqual(
            outcome.networkRuleNames,
            ["headers", "condition"],
            "the rewrite and the condition are credited in rule order, stubbed or not"
        )
    }

    func testMapLocalIsAlsoAStub() {
        let file = MapLocalFile(relativePath: "fixtures/users.json", statusCode: 200, contentType: "application/json", delay: 0)
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [rule("file", actions: NetworkRuleActions(stub: .mapLocal(file)))])
        XCTAssertEqual(outcome.stub, .mapLocal(file))
    }

    /// Precedence is rule order, whichever way round the two rules are. The merged outcome names
    /// a header once, so the engine adjudicates instead of leaving the consumer to.
    func testALaterRemoveBeatsAnEarlierSet() {
        let rules = [
            rule("sets", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["Authorization": "Bearer test"], remove: []))),
            rule("removes", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: [:], remove: ["Authorization"]))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertNil(rewrite?.set["Authorization"], "the later remove wins outright")
        XCTAssertEqual(rewrite?.remove, ["Authorization"])
    }

    /// Within one rewrite there is no rule order to appeal to, so `set` is applied before
    /// `remove` and a header named in both ends up removed.
    func testWithinOneRewriteRemoveStillBeatsSet() {
        let rules = [
            rule("both", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(
                set: ["Authorization": "Bearer test"],
                remove: ["Authorization"]
            ))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertNil(rewrite?.set["Authorization"])
        XCTAssertEqual(rewrite?.remove, ["Authorization"])
    }

    /// Header names are case-insensitive on the wire, so two spellings are one header. Keying a
    /// case-sensitive dictionary let both survive into the merged rewrite, and which one
    /// `NSMutableURLRequest` ended up carrying depended on the order a Swift dictionary happened
    /// to iterate in — a coin flip re-tossed on every launch.
    func testTwoSpellingsOfOneHeaderNameResolveToOneWinner() {
        let rules = [
            rule("first", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["Authorization": "first"]))),
            rule("second", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["authorization": "second"]))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertEqual(rewrite?.set.count, 1, "two spellings of one header name are one header")
        XCTAssertEqual(rewrite?.set["authorization"], "second", "the later rule wins, under its own spelling")
    }

    /// And the case-insensitivity holds across the two operations: removing `AUTHORIZATION`
    /// cancels a set of `Authorization`, because they are the same header.
    func testARemoveCancelsAnEarlierSetSpelledInAnotherCase() {
        let rules = [
            rule("sets", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["Authorization": "Bearer test"]))),
            rule("removes", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(remove: ["AUTHORIZATION"]))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertTrue(rewrite?.set.isEmpty == true)
        XCTAssertEqual(rewrite?.remove, ["AUTHORIZATION"])
    }

    /// A rewrite that sets and removes nothing changes nothing, so it is not reported as a
    /// rewrite and its override is not credited with one. Reporting it cost the interceptor a
    /// second `saveRequest` of an untouched request.
    func testARewriteThatChangesNothingIsNeitherReportedNorCredited() {
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [
            rule("inert", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite())),
        ])
        XCTAssertNil(outcome.headerRewrite, "an empty rewrite is not a rewrite")
        XCTAssertEqual(outcome, .empty)
    }

    /// Credits are in rule order, not in facet order: an override that supplied the condition is
    /// named before a later one that rewrote headers.
    func testOverridesAreCreditedInRuleOrder() {
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [
            rule("slow", actions: NetworkRuleActions(condition: NetworkCondition(latency: 1))),
            rule("headers", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["A": "1"]))),
        ])
        XCTAssertEqual(outcome.networkRuleNames, ["slow", "headers"])
    }

    func testOneRuleCanStubRewriteAndConditionAtOnce() {
        let condition = NetworkCondition(latency: 2, bandwidthKBps: 64, failureRate: 0.5)
        let mock = MockResponse(statusCode: 201, headers: [:], bodyID: nil, delay: 0)
        let composed = rule("everything", actions: NetworkRuleActions(
            stub: .mock(mock),
            rewriteHeaders: NetworkHeaderRewrite(set: ["A": "1"], remove: ["B"]),
            condition: condition
        ))
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [composed])

        XCTAssertEqual(outcome.stub, .mock(mock))
        XCTAssertEqual(outcome.headerRewrite?.set["A"], "1")
        XCTAssertEqual(outcome.condition, condition)
    }

    /// The whole point of the change: a stub no longer suppresses a condition that matched, so
    /// "mock this endpoint and make it slow" is expressible with two overrides as well as one.
    func testAStubDoesNotSuppressAConditionFromAnotherRule() {
        let condition = NetworkCondition(latency: 3)
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [
            rule("mock", actions: anyMock),
            rule("slow", actions: NetworkRuleActions(condition: condition)),
        ])
        XCTAssertNotNil(outcome.stub)
        XCTAssertEqual(outcome.condition, condition)
        XCTAssertEqual(outcome.networkRuleNames, ["slow"])
    }

    func testStubbedCreditsNameTheStubFirstThenEverythingElse() {
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [
            rule("rewrite", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["A": "1"]))),
            rule("mock", actions: anyMock),
            rule("slow", actions: NetworkRuleActions(condition: NetworkCondition(latency: 1))),
        ])
        XCTAssertEqual(outcome.stubbedCredits.names, ["mock", "rewrite", "slow"])
        XCTAssertEqual(outcome.stubbedCredits.ids.count, 3)
    }

    func testStubbedCreditsNameARuleCarryingSeveralActionsOnlyOnce() {
        let composed = rule("everything", actions: NetworkRuleActions(
            stub: .mock(MockResponse()),
            condition: NetworkCondition(latency: 1)
        ))
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [composed])
        XCTAssertEqual(outcome.stubbedCredits.names, ["everything"])
        XCTAssertEqual(outcome.stubbedCredits.ids, [composed.id])
    }

    /// A rule that matched but whose every facet was already filled by an earlier rule did
    /// nothing, and is not credited for it.
    func testARuleWhoseConditionLostIsNotCredited() {
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [
            rule("first", actions: NetworkRuleActions(condition: NetworkCondition(latency: 1))),
            rule("second", actions: NetworkRuleActions(condition: NetworkCondition(latency: 9))),
        ])
        XCTAssertEqual(outcome.condition?.latency, 1)
        XCTAssertEqual(outcome.networkRuleNames, ["first"])
    }

    func testAnOverrideWithNoActionsChangesNothing() {
        let outcome = NetworkRuleEngine.outcome(for: request(),
                                                rules: [rule("inert", actions: NetworkRuleActions())])
        XCTAssertEqual(outcome, .empty)
    }

    /// The mirror image of ``testALaterRemoveBeatsAnEarlierSet()``: a later override that sets a
    /// header an earlier one removed wins, so re-ordering the list really does change the
    /// outcome. This is the assertion the two of them used to lack — both merely checked that the
    /// key appeared in `set` and in `remove`, which was true whichever rule was meant to win.
    func testALaterSetBeatsAnEarlierRemove() {
        let rules = [
            rule("removes", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: [:], remove: ["Authorization"]))),
            rule("sets", actions: NetworkRuleActions(rewriteHeaders: NetworkHeaderRewrite(set: ["Authorization": "Bearer test"], remove: []))),
        ]
        let rewrite = NetworkRuleEngine.outcome(for: request(), rules: rules).headerRewrite
        XCTAssertEqual(rewrite?.set["Authorization"], "Bearer test")
        XCTAssertEqual(rewrite?.remove, [], "the later set wins outright")
    }
}
