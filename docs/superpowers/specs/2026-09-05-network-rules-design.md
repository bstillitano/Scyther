# Network Rules: Mocking, Map Local, Conditioning and Header Rewriting

**Date:** 2026-09-05
**Status:** Approved design — ready for implementation planning
**Part:** 1 of 5 in the networking backlog (see Related Specs)

## Summary

One rule engine, evaluated at a single point in `HTTPInterceptorURLProtocol.startLoading()`, that
can divert or shape a request before it reaches the network. It backs three of the backlog's
networking features:

1. **Mock and map local** — return a canned status, headers and body, or a file from Scyther's
   sandbox, without a network call. Rules can be created from a captured response or imported
   from a HAR file.
2. **Network conditioning** — per-rule latency, bandwidth ceiling and random failure rate,
   applied per matching request rather than device-wide.
3. **Header rewriting** — set or remove headers on matching requests.

Rules are managed from a new **Networking → Network Rules** screen and from a public
`Scyther.network.rules` API, so a UI test run can install a mocked state before launch.

## Background

Confirmed in code on 2026-09-05:

- `HTTPInterceptorURLProtocol` (`Sources/Scyther/Features/NetworkLogger/`) is a `URLProtocol`
  subclass registered by `NetworkHelper.start()`. `canServeRequest(_:)` decides whether Scyther
  sees a request at all: it requires `Scyther.isStarted`, an `http(s)` URL, absence of the
  `Scyther_Internal_Network_Request` property, and no prefix match against
  `NetworkHelper.instance.ignoredURLs`.
- `startLoading()` currently does exactly two things: `model.saveRequest(request)`, then copies
  the request, stamps the internal-request property, and resumes a data task on a private
  `URLSession` whose delegate is the protocol itself. **This is the only place a request can be
  diverted before it leaves the app**, and nothing else in the codebase competes for it.
- The `URLSessionDataDelegate` callbacks forward to `client?` as data arrives:
  `didReceive response` → `client?.urlProtocol(_:didReceive:cacheStoragePolicy:)`,
  `didReceive data` → `client?.urlProtocol(_:didLoad:)`, and `didCompleteWithError` →
  `didFailWithError` or `urlProtocolDidFinishLoading`, after saving the model and adding it to
  `NetworkLogger`. Synthesising a response means calling that same trio directly.
- `HTTPRequest` stores bodies on disk (`getRequestBodyFilepath()`, `saveData(_:toFile:)`) rather
  than in memory, and exposes `requestURLComponents`, `requestMethod`, `requestHeaders`.
- `NetworkHelper` is a `Sendable` singleton whose mutable properties are `nonisolated(unsafe)`
  because they are read from `URLProtocol` callbacks on arbitrary threads.
- `NetworkLogHARBuilder` (3.9.0) writes HAR 1.2 with a full Codable model — `HARLog`, `HAREntry`,
  `HARRequest`, `HARResponse`, `HARContent`. Reading a HAR needs no new schema, only a decode
  path and a mapping to rules.
- Persistence convention: `UserDefaults.scyther` (suite `com.scyther.settings`), keys prefixed
  `Scyther.`. Facades on `Scyther` are `public static let` singletons (`servers`, `featureFlags`,
  `network`, `localization`).
- Menu convention: a `MenuItem` case with a stable `id`, a `localized(_:)` title, an SF Symbol,
  a section in `MenuSection.allSections`, search keywords and sub-page row labels in
  `MenuSearchIndex`, and a `destination(for:)` arm in `MenuView`.
- Every user-facing string goes through `localized(_:)` with its key in a fragment under
  `Scripts/localization/strings/`; a lint test fails the suite on any SwiftUI literal that
  bypasses it.

## Goals

- Divert, delay, fail or rewrite a request from one evaluation point, with no change to how
  unmatched requests behave.
- Create a mock from a response already captured in the log, in two taps, with no typing.
- Import a HAR file and get one mock rule per entry.
- Manage rules from the menu and from code, with rules surviving app launches.
- Make a mocked or conditioned response obvious in the log, and make active rules impossible to
  forget about.
- Keep the engine a pure function so matching, precedence and composition are unit-testable
  without a network.

## Non-Goals

- **Request breakpoints.** Pausing a live request is spec 2; this spec's matcher is designed to
  be reused there, but nothing here suspends a request.
- **Response body editing after the fact.** A rule returns a body it already holds; editing a
  real response as it streams belongs to breakpoints.
- **Rule sharing or sync.** Rules live on one device. Export/import beyond HAR is out of scope.
- **WebSocket rules.** A `URLProtocol` never sees `URLSessionWebSocketTask` (spec 5).
- **Regular expression matching.** Wildcard globs only, for the reason given under Matching.
- **Rewriting request bodies.** Headers only in this pass; body rewriting has no clear use case
  that mocking does not already cover.

## Design

### Component 1: The rule model (new, pure value types)

New directory `Sources/Scyther/Features/NetworkRules/`. All types `Codable` and `Sendable`.

```swift
public struct NetworkRule: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var match: NetworkRuleMatch
    public var action: NetworkRuleAction
}

public struct NetworkRuleMatch: Codable, Sendable, Equatable {
    /// Uppercased HTTP methods. Empty matches any method.
    public var methods: Set<String>
    /// Host pattern, e.g. `api.example.com` or `*.example.com`. Nil matches any host.
    public var host: NetworkRulePattern?
    /// Path pattern, e.g. `/v1/users` or `/v1/*`. Nil matches any path.
    public var path: NetworkRulePattern?
    /// Query items that must all be present with these values. Empty matches any query.
    public var query: [String: String]
}

public struct NetworkRulePattern: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case exact, contains, wildcard }
    public var kind: Kind
    public var value: String
}

public enum NetworkRuleAction: Codable, Sendable, Equatable {
    case mock(MockResponse)
    case mapLocal(MapLocalFile)
    case rewriteHeaders(NetworkHeaderRewrite)
    case condition(NetworkCondition)
}

public struct MockResponse: Codable, Sendable, Equatable {
    public var statusCode: Int
    public var headers: [String: String]
    /// Body id; the bytes live on disk under the rules directory. Nil means an empty body.
    public var bodyID: UUID?
    public var delay: TimeInterval
}

public struct MapLocalFile: Codable, Sendable, Equatable {
    /// Path relative to the app's Documents directory, chosen with the file browser.
    public var relativePath: String
    public var statusCode: Int
    public var contentType: String?
    public var delay: TimeInterval
}

public struct NetworkHeaderRewrite: Codable, Sendable, Equatable {
    /// Headers to set, replacing any existing value.
    public var set: [String: String]
    /// Header names to remove.
    public var remove: [String]
}

public struct NetworkCondition: Codable, Sendable, Equatable {
    public var latency: TimeInterval          // seconds, added before the request is sent
    public var bandwidthKBps: Int?            // nil = unthrottled
    public var failureRate: Double            // 0...1
    public var failureCode: Int               // URLError.Code rawValue, default .notConnectedToInternet
}
```

**Matching semantics.** A rule matches when every non-empty facet matches. Host and path
comparisons are case-insensitive; `wildcard` supports `*` as "any run of characters" and nothing
else. `exact` and `contains` are literal. Query matching is a subset test, so `?page=2&sort=name`
matches a rule requiring `page=2`.

Wildcards rather than regular expressions: this UI is operated on a phone, often one-handed,
while debugging something else. `*.example.com/v1/*` is typeable; a regex is not, and a malformed
one fails silently at the worst moment.

### Component 2: `NetworkRuleEngine` (new, pure)

```swift
public struct RuleOutcome: Sendable, Equatable {
    /// Headers to apply to the outgoing request. Empty when no rewrite matched.
    public var headerRewrite: NetworkHeaderRewrite?
    /// Conditioning from the first matching condition rule.
    public var condition: NetworkCondition?
    /// A response to synthesise instead of making the request.
    public var stub: RuleStub?
    /// Names of every rule that contributed, oldest first, for the log badge and diagnostics.
    public var appliedRuleNames: [String]
}

public enum RuleStub: Sendable, Equatable {
    case mock(MockResponse)
    case mapLocal(MapLocalFile)
}

enum NetworkRuleEngine {
    static func outcome(for request: URLRequest, rules: [NetworkRule]) -> RuleOutcome
}
```

One pass over the enabled rules in stored order:

| Action | Composition |
| --- | --- |
| `rewriteHeaders` | **All** matching rules apply, in order. Later `set` wins on a key collision; `remove` is applied after all `set`s. |
| `condition` | **First** matching rule wins. Stacking latency from three rules would be surprising. |
| `mock` / `mapLocal` | **First** matching rule wins and short-circuits the network. |

A disabled rule is skipped entirely. When the master switch is off, `outcome` returns an empty
outcome without examining rules at all.

The engine takes its rules as a parameter and touches no global state, so every table above is
directly unit-testable.

### Component 3: `NetworkRuleStore` (new, persistence + the read path)

```swift
@MainActor
final class NetworkRuleStore: ObservableObject {
    static let shared: NetworkRuleStore
    @Published private(set) var rules: [NetworkRule]
    @Published var isEnabled: Bool        // master switch

    /// Adds a rule created in the UI. Persisted to the defaults suite.
    func add(_ rule: NetworkRule)
    /// Adds a rule created through the public API. Held in memory only; cleared on next launch.
    func addTransient(_ rule: NetworkRule)
    func update(_ rule: NetworkRule)
    func remove(id: UUID)
    func move(from: IndexSet, to: Int)    // order is precedence
    func setEnabled(_ enabled: Bool, id: UUID)
    func removeAll()

    func bodyURL(for id: UUID) -> URL
    func storeBody(_ data: Data) -> UUID
}
```

- Rules persist as JSON in `UserDefaults.scyther` under `Scyther.NetworkRules.Rules`; the master
  switch under `Scyther.NetworkRules.Enabled`.
- Mock bodies are written to `<Application Support>/Scyther/NetworkRules/<uuid>` rather than into
  defaults, mirroring how `HTTPRequest` keeps bodies on disk. Deleting a rule deletes its body.
- **Thread-safe read path.** The protocol callback runs on an arbitrary thread and cannot hop to
  the main actor without deadlocking the loading system. The store therefore publishes an
  immutable snapshot to a `nonisolated(unsafe)` holder guarded by an `NSLock`, refreshed on every
  mutation. `NetworkRuleSnapshot.current` returns `(isEnabled: Bool, rules: [NetworkRule])`, persisted
  rules first then transient ones, and is what the interceptor reads. This mirrors `NetworkHelper.instance.ignoredURLs`, which is already
  read from the same context.

### Component 4: `Scyther.network.rules` (public API)

```swift
public extension Network {
    var rules: NetworkRules { .shared }
}

public final class NetworkRules: Sendable {
    public func add(_ rule: NetworkRule)
    public func remove(id: UUID)
    public func removeAll()
    public var all: [NetworkRule] { get }
    public var isEnabled: Bool { get set }

}

// Ergonomic constructors on NetworkRule itself, so `add(.mock(...))` resolves by leading dot:
public extension NetworkRule {
    static func mock(name: String, matching: NetworkRuleMatch, returning: MockResponse) -> NetworkRule
    static func condition(name: String, matching: NetworkRuleMatch, _ condition: NetworkCondition) -> NetworkRule
    static func headers(name: String, matching: NetworkRuleMatch, set: [String: String], remove: [String]) -> NetworkRule
}

public extension NetworkRuleMatch {
    static func host(_ pattern: String, path: String? = nil, methods: Set<String> = []) -> NetworkRuleMatch
    static func path(_ pattern: String, methods: Set<String> = []) -> NetworkRuleMatch
}

public extension MockResponse {
    static func json(_ string: String, status: Int = 200, delay: TimeInterval = 0) -> MockResponse
    static func empty(status: Int, delay: TimeInterval = 0) -> MockResponse
}
```

Rules added through the API are held in a separate in-memory collection and are **not** written
to defaults, so a UI test run cannot leave rules behind on a device. Rules created in the UI
persist. `NetworkRule` itself carries no persistence flag — the store owns the distinction, so the
public model stays a plain value type. `all` returns persisted rules followed by transient ones,
which is also their precedence order, and this is stated in the API documentation.

### Component 5: Interceptor integration (modifies `HTTPInterceptorURLProtocol`)

`canServeRequest(_:)` is unchanged: a request Scyther would not log is a request rules do not
touch either.

`startLoading()` becomes:

1. `model.saveRequest(request)` (unchanged).
2. `let outcome = NetworkRuleEngine.outcome(for: request, rules: NetworkRuleSnapshot.current.rules)`
   — skipped entirely when the master switch is off.
3. Apply `outcome.headerRewrite` to the mutable copy before the internal-request property is set.
4. If `outcome.stub` is non-nil: after `delay`, synthesise the response (below) and return
   without creating a data task.
5. Otherwise apply `outcome.condition`: sleep `latency` before `resume()`; roll `failureRate` and,
   on a hit, call `client?.urlProtocol(self, didFailWithError: URLError(code))` and log the model
   as a failure; otherwise resume as today.

**Synthesising a stub** calls the same three client methods the real path uses:
`client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)`,
`client?.urlProtocol(self, didLoad: body)`, `client?.urlProtocolDidFinishLoading(self)`. The
`HTTPURLResponse` is built from the rule's status and headers against the original URL. The model
is saved and added to `NetworkLogger` exactly as a real response would be, so a mock appears in
the log with correct timing.

**Bandwidth throttling** is applied in `urlSession(_:dataTask:didReceive:)`: when
`bandwidthKBps` is set, data is forwarded to the client in chunks of that many bytes per second
rather than in one call. Latency and throttling both use `Thread.sleep` on the protocol's own
delegate queue, never the main thread.

`HTTPRequest` gains two fields:

```swift
/// Names of the rules that shaped this request, if any.
var appliedRuleNames: [String] = []
/// Whether the response was synthesised rather than received from the network.
var wasStubbed: Bool = false
```

`HTTPRequestView` shows a **MOCKED** lozenge using the same badge treatment as the GraphQL
operation badges, and `LogDetailsView` gains a Rules row listing the applied rule names.

### Component 6: UI

**Menu.** New `MenuItem.networkRules`, id `networkRules`, icon `arrow.triangle.branch`, in the
Networking section immediately after `.networkLogs`. Search keywords: `mock`, `stub`, `map local`,
`throttle`, `latency`, `offline`, `rewrite`, `charles`, `proxyman`. The row's detail text shows
the active rule count so rules are never silently on.

**Rule list** (`NetworkRulesView`): a master switch at the top, then rules grouped by action type
with an enable toggle each, drag to reorder (order is precedence), and swipe to delete. An empty
state explains what a rule does. A toolbar menu offers **New rule** and **Import from HAR**.

**Rule editor** (`NetworkRuleEditorView`): a Match section (method chips, host field with a
kind picker, path field, query rows) and an Action section whose fields swap with the picked
action. The mock body uses the existing `TextEntryView`; map local uses the existing file browser
to pick a file.

**Save as mock** (`LogDetailsView`): a row that creates a mock rule pre-filled from the captured
response — status, headers, body — matching that request's method, host and path exactly, then
opens the editor. This is the primary way rules get created; typing a body by hand is the
fallback.

**Import from HAR**: a file picker for a `.har`, decoded with the existing `HARLog` model,
creating one disabled mock rule per entry named `<method> <path>`. Rules arrive disabled so an
import cannot silently change app behaviour.

### Component 7: Testing

- `NetworkRuleEngineTests` — matching per facet (method, host exact/contains/wildcard, path,
  query subset), case-insensitivity, disabled rules skipped, master switch off, and the three
  composition rules in the table above including collision order for header sets.
- `NetworkRuleStoreTests` — persistence round-trip in a throwaway suite, body written and deleted
  with its rule, reordering changes precedence, API-added rules are not persisted.
- `NetworkRuleInterceptorTests` — a harness that registers the protocol against a local
  `URLProtocol` stub and asserts: a matched mock never reaches the network and returns the rule's
  status and body; a rewritten header arrives on the outgoing request; a failure rule surfaces the
  right `URLError`; a latency rule delays by at least the configured interval; an unmatched
  request is byte-identical to today's behaviour.
- `NetworkRuleHARImportTests` — a fixture HAR produces one rule per entry, disabled, with the
  entry's status, headers and body.
- Every new string is added to a `NetworkRules.json` fragment in all twelve languages; the
  existing catalog and lint tests cover it.

### Documentation

README gains a **Network Rules** subsection under Networking covering the three actions, the
save-as-mock flow, HAR import, and the public API with a UI-test example. A DocC article
`NetworkRules.md` covers the same for API consumers. `CONTRIBUTING.md` needs no change.

## Risks and mitigations

- **A rule matches more broadly than intended and silently breaks the app.** Mitigated three
  ways: the MOCKED badge in the log, the active rule count on the menu row, and the master switch.
  Imported HAR rules arrive disabled.
- **Blocking the URL loading system.** Latency and throttling sleep on the protocol's private
  delegate queue, never the main thread or a shared queue. Sleeps are capped at 30 seconds so a
  mistyped latency cannot appear to hang the app forever.
- **Rules outliving a debugging session.** API-created rules never persist; UI-created rules do,
  and the menu row's count is the reminder.
- **Public API stability.** The model types are `public` and `Codable`, so their stored shape is a
  compatibility surface. Decoding tolerates unknown action cases by skipping the rule rather than
  failing the whole store.

## Related specs

| # | Spec | Depends on |
| --- | --- | --- |
| 1 | Network Rules (this document) | — |
| 2 | Request Breakpoints | `NetworkRuleMatch`, the `startLoading` hook |
| 3 | Request Replay and Editor | `HTTPRequest`; independent of the engine |
| 4 | Traffic Stats and Waterfall | `NetworkLogger`; independent |
| 5 | WebSocket Logging | independent; needs its own capture mechanism |
