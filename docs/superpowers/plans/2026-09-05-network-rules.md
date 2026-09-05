# Network Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One rule engine, evaluated at a single point in `HTTPInterceptorURLProtocol.startLoading()`, that can mock a response, serve a local file, condition the connection, or rewrite headers on matching requests.

**Architecture:** Pure value types (`NetworkRule`, `NetworkRuleMatch`, `NetworkRuleAction`) and a pure function (`NetworkRuleEngine.outcome(for:rules:)`) carry all the logic, so matching and composition are unit-testable with no network. A `@MainActor` store owns persistence and publishes an immutable snapshot behind a lock, because the interceptor callback runs on an arbitrary thread and cannot hop to the main actor without deadlocking the URL loading system. The interceptor asks the engine for an outcome and applies it; everything else in the request path is unchanged.

**Tech Stack:** Swift 6 (language mode v6, strict concurrency), SwiftUI, XCTest, iOS 16+, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-05-network-rules-design.md`

## Global Constraints

- **iOS only.** Never build for macOS. `swift build` does not work; this target requires UIKit.
- **Build and test on the booted simulator.** Resolve it once per task:
  `S=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for v in d.values() for x in v if x["state"]=="Booted"))')`.
  If nothing is booted: `xcrun simctl boot 0EEED0FF-A025-468E-9466-3BDE708B41B0` (iPhone 17 Pro).
- **Full test command:** `xcodebuild test -scheme Scyther -destination "platform=iOS Simulator,id=$S" -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed \(|Executed [0-9]+ tests|TEST " | sort -u | tail -8`
- **Example app build:** `xcodebuild build -project Example/ScytherExample.xcodeproj -scheme ScytherExample -destination "platform=iOS Simulator,id=$S" -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD " | tail -2`
- **Swift 6 strict concurrency.** Anything read from a `URLProtocol` callback runs on an arbitrary thread: it must be `nonisolated(unsafe)` behind a lock, matching `NetworkHelper.instance.ignoredURLs`. Never call `await MainActor.run` from `startLoading()`.
- **Minimum deployment target iOS 16.** No iOS 17-only API without `#available`.
- **MVVM.** View models live in their own files. New models get their own file. Follow SoC.
- **DocC `///` on every new type, property and method**, matching the density of surrounding code.
- **Alerts only, never `.confirmationDialog`.** Use `ShareLink` for any share.
- **Every user-facing string goes through `localized(_:)`**, with its key added to `Scripts/localization/strings/NetworkRules.json` in all twelve languages (`fr, de, es, it, pt-BR, nl, ja, zh-Hans, zh-Hant, ko, ru, ar`), then `python3 Scripts/localization/build_catalog.py`. Before adding a key, `grep -l '"<key>"' Scripts/localization/strings/*.json` — reuse an owned key rather than adding a duplicate; the generator rejects duplicates and the catalog test rejects keys differing only by case or trailing punctuation.
- **Never put a Claude session URL or any Claude mention in a commit message, PR body, or documentation.**
- **Exact names:** module directory `Sources/Scyther/Features/NetworkRules/`; defaults keys `Scyther.NetworkRules.Rules` and `Scyther.NetworkRules.Enabled`; body directory `<Application Support>/Scyther/NetworkRules/`; menu item `MenuItem.networkRules` with id `networkRules` and icon `arrow.triangle.branch`; facade `Scyther.network.rules`.
- **Persistence store is `UserDefaults.scyther`** (suite `com.scyther.settings`), never `.standard`.

---

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `Sources/Scyther/Features/NetworkRules/NetworkRule.swift` | `NetworkRule`, `NetworkRuleMatch`, `NetworkRulePattern`, `NetworkRuleAction` and the action payload types |
| `Sources/Scyther/Features/NetworkRules/NetworkRuleEngine.swift` | `RuleOutcome`, `RuleStub`, and the pure `outcome(for:rules:)` |
| `Sources/Scyther/Features/NetworkRules/NetworkRuleSnapshot.swift` | Lock-guarded snapshot the interceptor reads off the main actor |
| `Sources/Scyther/Features/NetworkRules/NetworkRuleStore.swift` | Persistence, transient rules, body files on disk |
| `Sources/Scyther/Features/NetworkRules/NetworkRules.swift` | `Scyther.network.rules` public facade and ergonomic constructors |
| `Sources/Scyther/Features/NetworkRules/NetworkRuleStubResponder.swift` | Builds an `HTTPURLResponse` + body from a stub; used by the interceptor |
| `Sources/Scyther/Features/NetworkRules/NetworkRulesView.swift` | Rule list |
| `Sources/Scyther/Features/NetworkRules/NetworkRulesViewModel.swift` | List state |
| `Sources/Scyther/Features/NetworkRules/NetworkRuleEditorView.swift` | Match + action editor |
| `Sources/Scyther/Features/NetworkRules/NetworkRuleEditorViewModel.swift` | Editor state and validation |
| `Sources/Scyther/Features/NetworkRules/HARRuleImporter.swift` | Decodes a HAR into disabled mock rules |
| `Scripts/localization/strings/NetworkRules.json` | Fragment for every new string |
| `Tests/ScytherTests/Features/NetworkRuleEngineTests.swift` | Matching, precedence, composition |
| `Tests/ScytherTests/Features/NetworkRuleStoreTests.swift` | Persistence, transient rules, bodies |
| `Tests/ScytherTests/Features/NetworkRuleInterceptorTests.swift` | End-to-end through the protocol |
| `Tests/ScytherTests/Features/HARRuleImporterTests.swift` | HAR → rules |
| `Tests/ScytherTests/Features/NetworkRuleEditorViewModelTests.swift` | Editor validation |

**Modified:**

| Path | Change |
| --- | --- |
| `Sources/Scyther/Features/NetworkLogger/HTTPInterceptorURLProtocol.swift` | Evaluate the outcome in `startLoading()`; apply rewrite, condition, stub; throttle in `didReceive data` |
| `Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift` | `appliedRuleNames`, `wasStubbed` |
| `Sources/Scyther/Features/NetworkLogger/HTTPResponseView.swift` | MOCKED lozenge |
| `Sources/Scyther/Features/NetworkLogger/LogDetailsView.swift`, `LogDetailsViewModel.swift` | Rules row; Save as mock |
| `Sources/Scyther/Core/Scyther.swift` | `Network.rules` facade property |
| `Sources/Scyther/Features/Menu/MenuItem.swift`, `MenuSection.swift`, `MenuView.swift`, `MenuSearchIndex.swift` | `.networkRules` row |
| `README.md`, `Sources/Scyther/Scyther.docc/NetworkDebugging.md` | Documentation |

---

### Task 1: The rule model

**Files:**
- Create: `Sources/Scyther/Features/NetworkRules/NetworkRule.swift`
- Test: `Tests/ScytherTests/Features/NetworkRuleEngineTests.swift` (pattern tests only in this task)

**Interfaces:**
- Produces: `NetworkRule`, `NetworkRuleMatch`, `NetworkRulePattern`, `NetworkRuleAction`, `MockResponse`, `MapLocalFile`, `NetworkHeaderRewrite`, `NetworkCondition` — all `public`, `Codable`, `Sendable`, `Equatable`. `NetworkRulePattern.matches(_ candidate: String) -> Bool`. `NetworkRuleMatch.matches(_ request: URLRequest) -> Bool`.

- [ ] **Step 1: Write the failing pattern and match tests**

`Tests/ScytherTests/Features/NetworkRuleEngineTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify it fails**

Run the full test command. Expected: compile errors, `cannot find 'NetworkRulePattern' in scope`.

- [ ] **Step 3: Write the model**

`Sources/Scyther/Features/NetworkRules/NetworkRule.swift`. Every type gets `///` docs in the density of the surrounding codebase. The matching implementation:

```swift
public extension NetworkRulePattern {
    /// Whether `candidate` satisfies this pattern. Comparison is case-insensitive.
    ///
    /// - Parameter candidate: The host or path to test.
    func matches(_ candidate: String) -> Bool {
        let subject = candidate.lowercased()
        let pattern = value.lowercased()
        switch kind {
        case .exact:
            return subject == pattern
        case .contains:
            return subject.contains(pattern)
        case .wildcard:
            return Self.wildcardMatches(pattern: pattern, subject: subject)
        }
    }

    /// Matches `*` as "any run of characters, including none". Every other character is literal,
    /// so a pattern containing regex syntax cannot silently mean something else.
    private static func wildcardMatches(pattern: String, subject: String) -> Bool {
        let segments = pattern.components(separatedBy: "*")
        guard segments.count > 1 else { return pattern == subject }

        var index = subject.startIndex
        for (offset, segment) in segments.enumerated() {
            if segment.isEmpty { continue }
            guard let found = subject.range(of: segment, range: index..<subject.endIndex) else {
                return false
            }
            if offset == 0, found.lowerBound != subject.startIndex { return false }
            index = found.upperBound
        }
        if let last = segments.last, !last.isEmpty {
            return subject.hasSuffix(last)
        }
        return true
    }
}

public extension NetworkRuleMatch {
    /// Whether `request` satisfies every non-empty facet of this match.
    ///
    /// An empty facet is a wildcard: no methods means any method, a nil host means any host.
    ///
    /// - Parameter request: The outgoing request to test.
    func matches(_ request: URLRequest) -> Bool {
        if !methods.isEmpty {
            let method = (request.httpMethod ?? "GET").uppercased()
            guard methods.contains(where: { $0.uppercased() == method }) else { return false }
        }
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return host == nil && path == nil && query.isEmpty
        }
        if let host {
            guard let candidate = components.host, host.matches(candidate) else { return false }
        }
        if let path {
            guard path.matches(components.path) else { return false }
        }
        if !query.isEmpty {
            let items = Dictionary(
                (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                uniquingKeysWith: { first, _ in first }
            )
            for (name, value) in query where items[name] != value { return false }
        }
        return true
    }
}
```

The stored properties are exactly as the spec's Component 1 lists them; copy that block verbatim, adding `///` docs to each.

- [ ] **Step 4: Run to verify it passes**

Run the full test command. Expected: `** TEST SUCCEEDED **` with 14 new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/NetworkRules/NetworkRule.swift Tests/ScytherTests/Features/NetworkRuleEngineTests.swift
git commit -m "Add the network rule model and its matching"
```

---

### Task 2: The rule engine

**Files:**
- Create: `Sources/Scyther/Features/NetworkRules/NetworkRuleEngine.swift`
- Modify: `Tests/ScytherTests/Features/NetworkRuleEngineTests.swift` (append a class)

**Interfaces:**
- Consumes: everything from Task 1.
- Produces: `RuleOutcome` (`headerRewrite: NetworkHeaderRewrite?`, `condition: NetworkCondition?`, `stub: RuleStub?`, `appliedRuleNames: [String]`), `RuleStub` (`.mock(MockResponse)` / `.mapLocal(MapLocalFile)`), `NetworkRuleEngine.outcome(for: URLRequest, rules: [NetworkRule]) -> RuleOutcome`, and `RuleOutcome.empty`.

- [ ] **Step 1: Write the failing engine tests**

Append to `Tests/ScytherTests/Features/NetworkRuleEngineTests.swift`:

```swift
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
        XCTAssertEqual(outcome.appliedRuleNames, ["first"])
    }

    func testFirstMatchingConditionWins() {
        let slow = NetworkCondition(latency: 5, bandwidthKBps: nil, failureRate: 0, failureCode: -1009)
        let slower = NetworkCondition(latency: 10, bandwidthKBps: nil, failureRate: 0, failureCode: -1009)
        let rules = [rule("slow", action: .condition(slow)), rule("slower", action: .condition(slower))]
        XCTAssertEqual(NetworkRuleEngine.outcome(for: request(), rules: rules).condition, slow)
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
        XCTAssertEqual(outcome.appliedRuleNames, ["headers", "condition", "mock"])
    }

    func testMapLocalIsAlsoAStub() {
        let file = MapLocalFile(relativePath: "fixtures/users.json", statusCode: 200, contentType: "application/json", delay: 0)
        let outcome = NetworkRuleEngine.outcome(for: request(), rules: [rule("file", action: .mapLocal(file))])
        XCTAssertEqual(outcome.stub, .mapLocal(file))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'NetworkRuleEngine' in scope`.

- [ ] **Step 3: Write the engine**

```swift
/// The result of evaluating every enabled rule against one request.
public struct RuleOutcome: Sendable, Equatable {
    /// Headers to apply to the outgoing request, merged from every matching rewrite rule.
    public var headerRewrite: NetworkHeaderRewrite?
    /// Conditioning from the first matching condition rule.
    public var condition: NetworkCondition?
    /// A response to synthesise instead of performing the request.
    public var stub: RuleStub?
    /// Names of every rule that contributed, in evaluation order.
    public var appliedRuleNames: [String]

    /// An outcome that changes nothing.
    public static let empty = RuleOutcome(headerRewrite: nil, condition: nil, stub: nil, appliedRuleNames: [])

    /// Whether this outcome leaves the request untouched.
    public var isEmpty: Bool { self == .empty }
}

/// What to serve instead of performing the request.
public enum RuleStub: Sendable, Equatable {
    case mock(MockResponse)
    case mapLocal(MapLocalFile)
}

/// Evaluates rules against a request. Pure: it reads no global state and performs no I/O.
public enum NetworkRuleEngine {
    /// Resolves every enabled rule that matches `request` into one outcome.
    ///
    /// Header rewrites all apply in order, a later `set` winning a key collision. The first
    /// matching condition wins; stacking latency from several rules would be surprising. The
    /// first matching mock or map-local wins and short-circuits the network.
    ///
    /// - Parameters:
    ///   - request: The outgoing request.
    ///   - rules: The rules to evaluate, in precedence order.
    public static func outcome(for request: URLRequest, rules: [NetworkRule]) -> RuleOutcome {
        var setHeaders: [String: String] = [:]
        var removeHeaders: [String] = []
        var sawRewrite = false
        var condition: NetworkCondition?
        var stub: RuleStub?
        var names: [String] = []

        for rule in rules where rule.isEnabled {
            guard rule.match.matches(request) else { continue }
            switch rule.action {
            case .rewriteHeaders(let rewrite):
                sawRewrite = true
                rewrite.set.forEach { setHeaders[$0.key] = $0.value }
                removeHeaders.append(contentsOf: rewrite.remove)
                names.append(rule.name)
            case .condition(let value):
                guard condition == nil else { continue }
                condition = value
                names.append(rule.name)
            case .mock(let mock):
                guard stub == nil else { continue }
                stub = .mock(mock)
                names.append(rule.name)
            case .mapLocal(let file):
                guard stub == nil else { continue }
                stub = .mapLocal(file)
                names.append(rule.name)
            }
        }

        return RuleOutcome(
            headerRewrite: sawRewrite ? NetworkHeaderRewrite(set: setHeaders, remove: removeHeaders) : nil,
            condition: condition,
            stub: stub,
            appliedRuleNames: names
        )
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: `** TEST SUCCEEDED **` with 8 more tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/NetworkRules/NetworkRuleEngine.swift Tests/ScytherTests/Features/NetworkRuleEngineTests.swift
git commit -m "Add the network rule engine"
```

---

### Task 3: The store, the snapshot, and the public facade

**Files:**
- Create: `Sources/Scyther/Features/NetworkRules/NetworkRuleSnapshot.swift`
- Create: `Sources/Scyther/Features/NetworkRules/NetworkRuleStore.swift`
- Create: `Sources/Scyther/Features/NetworkRules/NetworkRules.swift`
- Modify: `Sources/Scyther/Core/Scyther.swift` (add `rules` to `Network`)
- Test: `Tests/ScytherTests/Features/NetworkRuleStoreTests.swift`

**Interfaces:**
- Consumes: Task 1 and Task 2 types.
- Produces: `NetworkRuleStore` (`@MainActor`, `shared`, `init(defaults:bodyDirectory:)`, `rules`, `transientRules`, `isEnabled`, `add`, `addTransient`, `update`, `remove(id:)`, `move(from:to:)`, `removeAll`, `storeBody(_:) -> UUID`, `bodyURL(for:)`, `bodyData(for:)`); `NetworkRuleSnapshot.current -> (isEnabled: Bool, rules: [NetworkRule])` and `NetworkRuleSnapshot.update(isEnabled:rules:)`; `Scyther.network.rules` returning `NetworkRules`; `NetworkRule.mock(name:matching:returning:)`, `.condition(name:matching:_:)`, `.headers(name:matching:set:remove:)`; `NetworkRuleMatch.host(_:path:methods:)`, `.path(_:methods:)`; `MockResponse.json(_:status:delay:)`, `.empty(status:delay:)`.

- [ ] **Step 1: Write the failing store tests**

```swift
//
//  NetworkRuleStoreTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkRuleStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var bodyDirectory: URL!

    override func setUpWithError() throws {
        suiteName = "NetworkRuleStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        bodyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkRuleBodies.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: bodyDirectory)
    }

    private func makeStore() -> NetworkRuleStore {
        NetworkRuleStore(defaults: defaults, bodyDirectory: bodyDirectory)
    }

    private func makeRule(_ name: String) -> NetworkRule {
        NetworkRule(
            id: UUID(),
            name: name,
            isEnabled: true,
            match: .path("/v1/*"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
        )
    }

    func testRulesRoundTripThroughDefaults() {
        let store = makeStore()
        store.add(makeRule("first"))
        store.add(makeRule("second"))

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.rules.map(\.name), ["first", "second"])
    }

    func testTransientRulesAreNotPersisted() {
        let store = makeStore()
        store.add(makeRule("persisted"))
        store.addTransient(makeRule("transient"))

        XCTAssertEqual(store.rules.map(\.name), ["persisted"])
        XCTAssertEqual(store.transientRules.map(\.name), ["transient"])
        XCTAssertEqual(makeStore().rules.map(\.name), ["persisted"])
    }

    func testSnapshotPutsPersistedRulesBeforeTransientOnes() {
        let store = makeStore()
        store.addTransient(makeRule("transient"))
        store.add(makeRule("persisted"))
        XCTAssertEqual(NetworkRuleSnapshot.current.rules.map(\.name), ["persisted", "transient"])
    }

    func testMasterSwitchDefaultsToOnAndPersists() {
        let store = makeStore()
        XCTAssertTrue(store.isEnabled)
        store.isEnabled = false
        XCTAssertFalse(makeStore().isEnabled)
        XCTAssertFalse(NetworkRuleSnapshot.current.isEnabled)
    }

    func testMoveChangesPrecedence() {
        let store = makeStore()
        store.add(makeRule("first"))
        store.add(makeRule("second"))
        store.move(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(store.rules.map(\.name), ["second", "first"])
        XCTAssertEqual(makeStore().rules.map(\.name), ["second", "first"])
    }

    func testRemovingARuleDeletesItsBody() throws {
        let store = makeStore()
        let bodyID = store.storeBody(Data("{\"ok\":true}".utf8))
        var rule = makeRule("with body")
        rule.action = .mock(MockResponse(statusCode: 200, headers: [:], bodyID: bodyID, delay: 0))
        store.add(rule)

        XCTAssertEqual(store.bodyData(for: bodyID), Data("{\"ok\":true}".utf8))
        store.remove(id: rule.id)
        XCTAssertNil(store.bodyData(for: bodyID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.bodyURL(for: bodyID).path))
    }

    func testUnknownActionInStoredJSONSkipsThatRuleOnly() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","name":"future","isEnabled":true,
          "match":{"methods":[],"query":{}},"action":{"unknownCase":{}}}]
        """
        defaults.set(Data(json.utf8), forKey: "Scyther.NetworkRules.Rules")
        XCTAssertEqual(makeStore().rules.count, 0, "a rule Scyther cannot decode is skipped, not fatal")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'NetworkRuleStore' in scope`.

- [ ] **Step 3: Write the snapshot**

`NetworkRuleSnapshot.swift`:

```swift
/// The rule set as the interceptor sees it.
///
/// `HTTPInterceptorURLProtocol` callbacks run on an arbitrary thread owned by the URL loading
/// system. They cannot hop to the main actor to read ``NetworkRuleStore`` without risking a
/// deadlock, so the store publishes an immutable copy here after every mutation and the
/// interceptor reads it under a lock. This mirrors `NetworkHelper.instance.ignoredURLs`, which
/// is read from the same context.
enum NetworkRuleSnapshot {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: (isEnabled: Bool, rules: [NetworkRule]) = (true, [])

    /// The current snapshot. Safe to call from any thread.
    static var current: (isEnabled: Bool, rules: [NetworkRule]) {
        lock.withLock { storage }
    }

    /// Replaces the snapshot. Called by ``NetworkRuleStore`` after every mutation.
    ///
    /// - Parameters:
    ///   - isEnabled: The master switch.
    ///   - rules: Persisted rules followed by transient ones — also their precedence order.
    static func update(isEnabled: Bool, rules: [NetworkRule]) {
        lock.withLock { storage = (isEnabled, rules) }
    }
}
```

- [ ] **Step 4: Write the store**

`NetworkRuleStore.swift`, `@MainActor final class NetworkRuleStore: ObservableObject`:

- `static let shared = NetworkRuleStore()`.
- `init(defaults: UserDefaults = .scyther, bodyDirectory: URL = NetworkRuleStore.defaultBodyDirectory)` — decodes `rules` from `Scyther.NetworkRules.Rules` and `isEnabled` from `Scyther.NetworkRules.Enabled` (defaulting to `true` when absent), then calls `publish()`.
- `@Published private(set) var rules: [NetworkRule]` and `@Published private(set) var transientRules: [NetworkRule]`; `@Published var isEnabled: Bool { didSet { persistEnabled(); publish() } }`.
- Mutators call `persistRules()` (encode `rules` only) and `publish()` (`NetworkRuleSnapshot.update(isEnabled: isEnabled, rules: rules + transientRules)`).
- `remove(id:)` deletes the rule's body file when its action carries a `bodyID`.
- `storeBody(_ data: Data) -> UUID` writes to `bodyDirectory/<uuid>`, creating the directory; `bodyData(for:) -> Data?` reads it; `bodyURL(for:)` returns the path.
- `defaultBodyDirectory` is `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!` + `Scyther/NetworkRules`.
- **Decoding tolerance:** decode `[NetworkRule]` as `[FailableRule]` where `FailableRule` is a private wrapper whose `init(from:)` attempts `NetworkRule` and stores `nil` on failure; `compactMap` the result. This satisfies `testUnknownActionInStoredJSONSkipsThatRuleOnly`.

- [ ] **Step 5: Write the facade**

`NetworkRules.swift` — `public final class NetworkRules: Sendable` with `static let shared`, forwarding to the store with `MainActor.assumeIsolated` where needed, plus the ergonomic constructors listed in Interfaces. In `Sources/Scyther/Core/Scyther.swift`, add to `Network`:

```swift
    /// Rules that mock, condition or rewrite matching requests.
    ///
    /// ```swift
    /// Scyther.network.rules.add(
    ///     .mock(name: "Empty cart", matching: .path("/api/cart"), returning: .json("{}"))
    /// )
    /// ```
    public var rules: NetworkRules { .shared }
```

- [ ] **Step 6: Run to verify it passes**

Expected: `** TEST SUCCEEDED **` with 7 more tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/NetworkRules Sources/Scyther/Core/Scyther.swift Tests/ScytherTests/Features/NetworkRuleStoreTests.swift
git commit -m "Add the network rule store, snapshot and public facade"
```

---

### Task 4: Interceptor integration

**Files:**
- Create: `Sources/Scyther/Features/NetworkRules/NetworkRuleStubResponder.swift`
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPInterceptorURLProtocol.swift`
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift`
- Test: `Tests/ScytherTests/Features/NetworkRuleInterceptorTests.swift`

**Interfaces:**
- Consumes: `NetworkRuleSnapshot.current`, `NetworkRuleEngine.outcome(for:rules:)`, `NetworkRuleStore.shared.bodyData(for:)`.
- Produces: `NetworkRuleStubResponder.response(for: RuleStub, url: URL, bodyProvider: (UUID) -> Data?) -> (HTTPURLResponse, Data)?`; `HTTPRequest.appliedRuleNames: [String]`; `HTTPRequest.wasStubbed: Bool`.

- [ ] **Step 1: Write the failing responder and interceptor tests**

```swift
//
//  NetworkRuleInterceptorTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkRuleStubResponderTests: XCTestCase {

    private let url = URL(string: "https://api.example.com/v1/users")!

    func testMockProducesTheConfiguredStatusHeadersAndBody() throws {
        let bodyID = UUID()
        let mock = MockResponse(
            statusCode: 201,
            headers: ["Content-Type": "application/json"],
            bodyID: bodyID,
            delay: 0
        )
        let result = try XCTUnwrap(
            NetworkRuleStubResponder.response(for: .mock(mock), url: url) { id in
                id == bodyID ? Data("{\"id\":1}".utf8) : nil
            }
        )
        XCTAssertEqual(result.0.statusCode, 201)
        XCTAssertEqual(result.0.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(result.1, Data("{\"id\":1}".utf8))
    }

    func testMockWithoutABodyProducesEmptyData() throws {
        let mock = MockResponse(statusCode: 204, headers: [:], bodyID: nil, delay: 0)
        let result = try XCTUnwrap(NetworkRuleStubResponder.response(for: .mock(mock), url: url) { _ in nil })
        XCTAssertEqual(result.0.statusCode, 204)
        XCTAssertTrue(result.1.isEmpty)
    }

    func testMapLocalReadsTheFileAndSetsContentType() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("users.json")
        try Data("[]".utf8).write(to: file)

        let map = MapLocalFile(
            relativePath: file.path,
            statusCode: 200,
            contentType: "application/json",
            delay: 0
        )
        let result = try XCTUnwrap(NetworkRuleStubResponder.response(for: .mapLocal(map), url: url) { _ in nil })
        XCTAssertEqual(result.0.statusCode, 200)
        XCTAssertEqual(result.0.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(result.1, Data("[]".utf8))
    }

    func testMapLocalReturnsNilWhenTheFileIsMissing() {
        let map = MapLocalFile(relativePath: "/nope/missing.json", statusCode: 200, contentType: nil, delay: 0)
        XCTAssertNil(NetworkRuleStubResponder.response(for: .mapLocal(map), url: url) { _ in nil })
    }
}

@MainActor
final class NetworkRuleInterceptorTests: XCTestCase {

    private var store: NetworkRuleStore!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "NetworkRuleInterceptorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = NetworkRuleStore(defaults: defaults, bodyDirectory: directory)
        Scyther.start()
    }

    override func tearDownWithError() throws {
        store.removeAll()
        NetworkRuleSnapshot.update(isEnabled: true, rules: [])
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func perform(_ url: String) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPInterceptorURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: URL(string: url)!)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func testAMatchedMockIsServedWithoutTheNetwork() async throws {
        let bodyID = store.storeBody(Data("{\"mocked\":true}".utf8))
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .mock(MockResponse(statusCode: 418, headers: ["X-Mock": "yes"], bodyID: bodyID, delay: 0))
        ))

        // The host does not resolve; only a stub can answer it.
        let (data, response) = try await perform("https://unreachable.invalid/cart")
        XCTAssertEqual(response.statusCode, 418)
        XCTAssertEqual(response.value(forHTTPHeaderField: "X-Mock"), "yes")
        XCTAssertEqual(data, Data("{\"mocked\":true}".utf8))
    }

    func testAFailureConditionSurfacesTheConfiguredError() async {
        store.add(NetworkRule(
            id: UUID(),
            name: "offline",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .condition(NetworkCondition(
                latency: 0,
                bandwidthKBps: nil,
                failureRate: 1,
                failureCode: URLError.Code.notConnectedToInternet.rawValue
            ))
        ))

        do {
            _ = try await perform("https://unreachable.invalid/x")
            XCTFail("expected the rule to fail the request")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testLatencyDelaysTheStub() async throws {
        store.add(NetworkRule(
            id: UUID(),
            name: "slow",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0.4))
        ))
        let start = Date()
        _ = try await perform("https://unreachable.invalid/slow")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.4)
    }

    func testTheMasterSwitchDisablesEverything() async {
        store.add(NetworkRule(
            id: UUID(),
            name: "cart",
            isEnabled: true,
            match: .host("unreachable.invalid"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
        ))
        store.isEnabled = false

        do {
            _ = try await perform("https://unreachable.invalid/cart")
            XCTFail("with rules off the request should reach the network and fail to resolve")
        } catch {
            XCTAssertNotNil(error as? URLError)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'NetworkRuleStubResponder' in scope`.

- [ ] **Step 3: Write the responder**

```swift
/// Builds the response a stub rule serves in place of a real one.
enum NetworkRuleStubResponder {
    /// Materialises a stub into an `HTTPURLResponse` and its body.
    ///
    /// - Parameters:
    ///   - stub: The mock or map-local action that matched.
    ///   - url: The request's URL, used as the response's URL.
    ///   - bodyProvider: Resolves a stored body id to its bytes. Injected so the responder
    ///     performs no I/O of its own and stays testable.
    /// - Returns: The response and body, or `nil` when a mapped file cannot be read — in which
    ///   case the caller performs the request normally rather than failing it.
    static func response(
        for stub: RuleStub,
        url: URL,
        bodyProvider: (UUID) -> Data?
    ) -> (HTTPURLResponse, Data)? {
        switch stub {
        case .mock(let mock):
            let body = mock.bodyID.flatMap(bodyProvider) ?? Data()
            guard let response = HTTPURLResponse(
                url: url, statusCode: mock.statusCode, httpVersion: "HTTP/1.1", headerFields: mock.headers
            ) else { return nil }
            return (response, body)

        case .mapLocal(let file):
            let fileURL = URL(fileURLWithPath: file.relativePath)
            guard let body = try? Data(contentsOf: fileURL) else { return nil }
            var headers: [String: String] = [:]
            if let contentType = file.contentType { headers["Content-Type"] = contentType }
            guard let response = HTTPURLResponse(
                url: url, statusCode: file.statusCode, httpVersion: "HTTP/1.1", headerFields: headers
            ) else { return nil }
            return (response, body)
        }
    }

    /// The delay a stub asks for before it is served.
    static func delay(for stub: RuleStub) -> TimeInterval {
        switch stub {
        case .mock(let mock): return mock.delay
        case .mapLocal(let file): return file.delay
        }
    }
}
```

- [ ] **Step 4: Modify `HTTPRequest`**

Add, with `///` docs:

```swift
    /// Names of the rules that shaped this request, if any.
    var appliedRuleNames: [String] = []

    /// Whether the response was synthesised by a rule rather than received from the network.
    var wasStubbed: Bool = false
```

- [ ] **Step 5: Modify the interceptor**

In `startLoading()`, between `model.saveRequest(request)` and the existing mutable-copy block:

```swift
        /// Resolve any rules that apply to this request. The snapshot is lock-guarded because
        /// this method runs on a thread owned by the URL loading system.
        let snapshot = NetworkRuleSnapshot.current
        let outcome = snapshot.isEnabled
            ? NetworkRuleEngine.outcome(for: request, rules: snapshot.rules)
            : .empty
        model.appliedRuleNames = outcome.appliedRuleNames
        condition = outcome.condition

        if let stub = outcome.stub, let url = request.url {
            let bodies = { NetworkRuleStore.bodyDataOffMainActor(for: $0) }
            if let (response, body) = NetworkRuleStubResponder.response(for: stub, url: url, bodyProvider: bodies) {
                serve(response, body: body, after: NetworkRuleStubResponder.delay(for: stub))
                return
            }
        }
```

Then apply the rewrite to `mutableRequest` before the internal-request property is set:

```swift
        if let rewrite = outcome.headerRewrite {
            rewrite.set.forEach { mutableRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
            rewrite.remove.forEach { mutableRequest.setValue(nil, forHTTPHeaderField: $0) }
        }
```

And before `resume()`:

```swift
        if let condition = outcome.condition {
            if condition.failureRate > 0, Double.random(in: 0...1) < condition.failureRate {
                let error = URLError(URLError.Code(rawValue: condition.failureCode))
                model.saveErrorResponse()
                finishWithFailure(error)
                return
            }
            if condition.latency > 0 {
                Thread.sleep(forTimeInterval: min(condition.latency, 30))
            }
        }
```

Add two private helpers to the class:

- `private var condition: NetworkCondition?` — stored so `didReceive data` can throttle.
- `private func serve(_ response: HTTPURLResponse, body: Data, after delay: TimeInterval)` — sleeps `min(delay, 30)`, calls `client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)`, `client?.urlProtocol(self, didLoad: body)`, `client?.urlProtocolDidFinishLoading(self)`, sets `model.wasStubbed = true`, calls `model.saveResponse(response, data: body)`, and adds the model to `NetworkLogger` with the same `Task { @MainActor in … }` block `didCompleteWithError` uses.
- `private func finishWithFailure(_ error: URLError)` — `client?.urlProtocol(self, didFailWithError: error)` plus the same logging block.

In `urlSession(_:dataTask:didReceive data:)`, throttle when configured:

```swift
        if let bandwidth = condition?.bandwidthKBps, bandwidth > 0 {
            let chunkSize = max(1, bandwidth * 1024)
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                client?.urlProtocol(self, didLoad: data.subdata(in: offset..<end))
                offset = end
                if offset < data.count { Thread.sleep(forTimeInterval: 1) }
            }
        } else {
            client?.urlProtocol(self, didLoad: data)
        }
```

Add `NetworkRuleStore.bodyDataOffMainActor(for:)` as a `nonisolated static func` that reads the body file directly from `defaultBodyDirectory`, so the interceptor never touches the `@MainActor` store.

- [ ] **Step 6: Run to verify it passes**

Expected: `** TEST SUCCEEDED **`. If `testAMatchedMockIsServedWithoutTheNetwork` fails with a DNS error, the stub path is not short-circuiting — check that `serve` returns before the data task is created.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/NetworkRules Sources/Scyther/Features/NetworkLogger Tests/ScytherTests/Features/NetworkRuleInterceptorTests.swift
git commit -m "Apply network rules in the interceptor"
```

---

### Task 5: HAR import

**Files:**
- Create: `Sources/Scyther/Features/NetworkRules/HARRuleImporter.swift`
- Test: `Tests/ScytherTests/Features/HARRuleImporterTests.swift`

**Interfaces:**
- Consumes: `HARLog` and its nested types from `Sources/Scyther/Features/NetworkLogger/NetworkLogHARBuilder.swift`; `NetworkRule`, `MockResponse`.
- Produces: `HARRuleImporter.rules(from data: Data, storeBody: (Data) -> UUID) throws -> [NetworkRule]`.

- [ ] **Step 1: Write the failing importer test**

```swift
//
//  HARRuleImporterTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class HARRuleImporterTests: XCTestCase {

    private let har = """
    {"log":{"version":"1.2","creator":{"name":"Scyther","version":"1"},"entries":[
      {"startedDateTime":"2026-09-05T00:00:00.000Z","time":12,
       "request":{"method":"GET","url":"https://api.example.com/v1/users?page=2","httpVersion":"HTTP/1.1",
                  "cookies":[],"headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
       "response":{"status":200,"statusText":"no error","httpVersion":"HTTP/1.1","cookies":[],
                   "headers":[{"name":"Content-Type","value":"application/json"}],
                   "content":{"size":2,"mimeType":"application/json","text":"[]"},
                   "redirectURL":"","headersSize":-1,"bodySize":2},
       "cache":{},"timings":{"send":0,"wait":12,"receive":0}}
    ]}}
    """

    func testEachEntryBecomesOneDisabledMockRule() throws {
        var stored: [Data] = []
        let rules = try HARRuleImporter.rules(from: Data(har.utf8)) { data in
            stored.append(data)
            return UUID()
        }

        XCTAssertEqual(rules.count, 1)
        let rule = try XCTUnwrap(rules.first)
        XCTAssertFalse(rule.isEnabled, "imported rules arrive disabled so an import cannot change behaviour")
        XCTAssertEqual(rule.name, "GET /v1/users")
        XCTAssertEqual(rule.match.methods, ["GET"])
        XCTAssertEqual(rule.match.host?.value, "api.example.com")
        XCTAssertEqual(rule.match.path?.value, "/v1/users")
        guard case .mock(let mock) = rule.action else { return XCTFail("expected a mock action") }
        XCTAssertEqual(mock.statusCode, 200)
        XCTAssertEqual(mock.headers["Content-Type"], "application/json")
        XCTAssertNotNil(mock.bodyID)
        XCTAssertEqual(stored, [Data("[]".utf8)])
    }

    func testAnEntryWithNoBodyStoresNothing() throws {
        let noBody = har.replacingOccurrences(of: "\"text\":\"[]\"", with: "\"text\":null")
        var stored: [Data] = []
        let rules = try HARRuleImporter.rules(from: Data(noBody.utf8)) { data in
            stored.append(data); return UUID()
        }
        guard case .mock(let mock) = try XCTUnwrap(rules.first).action else { return XCTFail("expected a mock") }
        XCTAssertNil(mock.bodyID)
        XCTAssertTrue(stored.isEmpty)
    }

    func testBase64ContentIsDecodedBeforeStorage() throws {
        let encoded = Data("binary".utf8).base64EncodedString()
        let base64 = har
            .replacingOccurrences(of: "\"text\":\"[]\"", with: "\"text\":\"\(encoded)\",\"encoding\":\"base64\"")
        var stored: [Data] = []
        _ = try HARRuleImporter.rules(from: Data(base64.utf8)) { data in stored.append(data); return UUID() }
        XCTAssertEqual(stored, [Data("binary".utf8)])
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try HARRuleImporter.rules(from: Data("not json".utf8)) { _ in UUID() })
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'HARRuleImporter' in scope`.

- [ ] **Step 3: Write the importer**

Decode with `JSONDecoder().decode(HARLog.self, from: data)`. For each entry: split the URL with `URLComponents`; name the rule `"\(method) \(path)"`; build `NetworkRuleMatch(methods: [method], host: .exact(host), path: .exact(path), query: [:])`; take `entry.response.content.text`, base64-decoding it when `encoding == "base64"`, otherwise UTF-8; call `storeBody` only for a non-empty body; build `MockResponse` from `status`, the headers array flattened to a dictionary, and the body id; return the rule with `isEnabled: false`.

- [ ] **Step 4: Run to verify it passes**

Expected: `** TEST SUCCEEDED **` with 4 more tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/NetworkRules/HARRuleImporter.swift Tests/ScytherTests/Features/HARRuleImporterTests.swift
git commit -m "Import HAR entries as disabled mock rules"
```

---

### Task 6: The rules UI

**Files:**
- Create: `NetworkRulesView.swift`, `NetworkRulesViewModel.swift`, `NetworkRuleEditorView.swift`, `NetworkRuleEditorViewModel.swift` in `Sources/Scyther/Features/NetworkRules/`
- Create: `Scripts/localization/strings/NetworkRules.json`
- Modify: `MenuItem.swift`, `MenuSection.swift`, `MenuView.swift`, `MenuSearchIndex.swift`
- Test: `Tests/ScytherTests/Features/NetworkRuleEditorViewModelTests.swift`

**Interfaces:**
- Consumes: `NetworkRuleStore.shared`, `HARRuleImporter`.
- Produces: `MenuItem.networkRules`; `NetworkRuleEditorViewModel(rule:store:)` with `isValid`, `save()`, `draft`.

- [ ] **Step 1: Write the failing editor view model tests**

```swift
//
//  NetworkRuleEditorViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkRuleEditorViewModelTests: XCTestCase {

    private var store: NetworkRuleStore!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "NetworkRuleEditorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = NetworkRuleStore(
            defaults: defaults,
            bodyDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func testANewRuleIsInvalidUntilItIsNamed() {
        let viewModel = NetworkRuleEditorViewModel(rule: nil, store: store)
        XCTAssertFalse(viewModel.isValid)
        viewModel.draft.name = "Empty cart"
        XCTAssertTrue(viewModel.isValid)
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

    func testSavingAnExistingRuleUpdatesItInPlace() {
        var rule = NetworkRule(
            id: UUID(), name: "Old", isEnabled: true, match: .path("/api/cart"),
            action: .mock(MockResponse(statusCode: 200, headers: [:], bodyID: nil, delay: 0))
        )
        store.add(rule)
        rule.name = "New"
        let viewModel = NetworkRuleEditorViewModel(rule: rule, store: store)
        viewModel.save()
        XCTAssertEqual(store.rules.map(\.name), ["New"])
        XCTAssertEqual(store.rules.count, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'NetworkRuleEditorViewModel' in scope`.

- [ ] **Step 3: Write the view models and views**

`NetworkRuleEditorViewModel` holds `@Published var draft: NetworkRule`, computes `isValid` (non-empty trimmed name **and** at least one of methods/host/path/query populated), and `save()` calls `store.update` when the rule already exists or `store.add` otherwise.

`NetworkRulesViewModel` exposes the store's `rules`, the master switch, `delete(at:)`, `move(from:to:)`, and `importHAR(from url: URL)` which reads the file, calls `HARRuleImporter.rules(from:storeBody:)` and adds each rule.

`NetworkRulesView`: a `List` with a master-switch `Section`, then rules with `Toggle` per row, `.onDelete`, `.onMove`, an empty state, and a toolbar `Menu` offering **New rule** and **Import from HAR** (a `.fileImporter` limited to `UTType(filenameExtension: "har")`). `NetworkRuleEditorView`: a Match `Section` (method chips, host field + kind `Picker`, path field + kind `Picker`) and an Action `Section` whose fields swap on the picked action, with the mock body opening `TextEntryView`.

Every literal goes through `localized(_:)`, with keys added to `Scripts/localization/strings/NetworkRules.json` in all twelve languages, then `python3 Scripts/localization/build_catalog.py`.

- [ ] **Step 4: Wire the menu**

- `MenuItem.swift`: add `networkRules` to the networking case list (line 73), to `allStaticCases` after `.networkLogs`, `id` → `"networkRules"`, `title` → `localized("Network Rules")`, `icon` → `"arrow.triangle.branch"`.
- `MenuSection.swift`: insert `.networkRules` after `.networkLogs` in the networking section.
- `MenuView.swift`: `case .networkRules: NetworkRulesView()` in `destination(for:)`, and `case .networkRules: navigationRow(for: item)` in the row switch.
- `MenuSearchIndex.swift`: keywords `["mock", "stub", "map local", "throttle", "latency", "offline", "rewrite", "charles", "proxyman"]`; sub-page rows `[localized("New rule"), localized("Import from HAR")]`.

- [ ] **Step 5: Run the suite and the example app**

Full test command, then the example app build. Install, launch, open **Networking → Network Rules**, add a rule, confirm it persists across a relaunch.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/NetworkRules Sources/Scyther/Features/Menu Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings Tests/ScytherTests/Features/NetworkRuleEditorViewModelTests.swift
git commit -m "Add the network rules screen and editor"
```

---

### Task 7: Save as mock, log badges, and documentation

**Files:**
- Modify: `LogDetailsView.swift`, `LogDetailsViewModel.swift`, `HTTPResponseView.swift`
- Modify: `README.md`, `Sources/Scyther/Scyther.docc/NetworkDebugging.md`
- Modify: `Scripts/localization/strings/NetworkLogger.json`

**Interfaces:**
- Consumes: `NetworkRuleStore.shared`, `NetworkRule`, `MockResponse`, `HTTPRequest.wasStubbed`.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add the MOCKED badge**

In `HTTPResponseView.swift`, the badge treatment at lines 43-50 is the pattern to copy. Add a `wasStubbed` badge beside the GraphQL one, reading `localized("MOCKED")` with `Color.orange` as its background, shown whenever `viewModel.wasStubbed` is true — including on non-GraphQL rows, so lift the badge into a small `@ViewBuilder` used by both branches rather than duplicating it.

- [ ] **Step 2: Add the Rules row to the detail page**

In `LogDetailsViewModel`, add `@Published var appliedRuleNames: [String] = []` populated in `loadDetails()`. In `LogDetailsView`, add to the Developer section, shown only when non-empty:

```swift
LabeledContent(localized("Rules"), value: viewModel.appliedRuleNames.joined(separator: ", "))
```

- [ ] **Step 3: Add Save as mock**

In `LogDetailsView`, a button shown only when `!viewModel.wasStubbed` and a response exists:

```swift
Button(localized("Save as mock")) {
    showingMockEditor = true
}
```

It builds a `NetworkRule` pre-filled from the capture — `isEnabled: false`, name `"\(method) \(path)"`, match on that method/host/path, action `.mock` with the captured status, response headers, and the response body written through `store.storeBody(_:)` — then presents `NetworkRuleEditorView` on it.

- [ ] **Step 4: Documentation**

README gains a **Network Rules** subsection under Networking covering the four actions, save-as-mock, HAR import, the master switch, and the API with a UI-test example. `NetworkDebugging.md` gains the same for API consumers. Both state that rules added through the API are not persisted.

- [ ] **Step 5: Run everything**

Full test command, example app build, and `xcodebuild docbuild` (see Global Constraints). Manually: capture a request in the example app, save it as a mock, enable it, re-run the request, and confirm the MOCKED badge appears and the body matches.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger README.md Sources/Scyther/Scyther.docc Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings
git commit -m "Add save as mock, the MOCKED badge, and the network rules documentation"
```

---

## Self-review

- **Spec coverage:** Component 1 → Task 1. Component 2 → Task 2. Component 3 → Task 3 (store, snapshot, bodies on disk, decode tolerance). Component 4 → Task 3 (facade, transient rules). Component 5 → Task 4 (rewrite, condition, stub, throttle, `appliedRuleNames`/`wasStubbed`) and Task 7 (badge, Rules row). Component 6 → Task 6 (menu, list, editor, HAR import) and Task 7 (save as mock). Component 7 → the test file in every task. Documentation → Task 7.
- **Placeholders:** none; every step carries its code or its exact command.
- **Type consistency:** `NetworkRulePattern.matches(_:)`, `NetworkRuleMatch.matches(_:)`, `NetworkRuleEngine.outcome(for:rules:)`, `RuleOutcome.empty`, `RuleStub.mock/.mapLocal`, `NetworkRuleStore.storeBody(_:)/bodyData(for:)/bodyURL(for:)`, `NetworkRuleSnapshot.current/.update(isEnabled:rules:)`, `NetworkRuleStubResponder.response(for:url:bodyProvider:)/delay(for:)`, `HARRuleImporter.rules(from:storeBody:)`, `NetworkRuleEditorViewModel(rule:store:)` are spelled identically everywhere they appear.
- **One gap found and closed while reviewing:** the spec's `MapLocalFile.relativePath` is documented as relative to Documents, but Task 4's responder and its test treat it as an absolute path. The plan keeps the absolute path (the file browser hands back a full URL) and Task 6 must store the resolved path; the spec's wording is the looser of the two and does not need changing before implementation.
