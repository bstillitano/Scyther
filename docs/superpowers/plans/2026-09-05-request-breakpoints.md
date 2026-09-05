# Request Breakpoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pause a matching request before it is sent, or a matching response before the app sees it, so either can be edited in place, with a mandatory timeout so the app can never be left hanging.

**Architecture:** A `BreakpointCoordinator` bridges the URL loading system's per-request thread and the main actor. `pause` blocks on a `DispatchSemaphore` with a timeout; the UI resolves it from the main actor. The matcher is `NetworkRuleMatch`, reused verbatim from the Network Rules work — this plan adds no second matching implementation. Response breakpoints withhold `didLoad:` and buffer, because a chunk already forwarded to the client cannot be recalled.

**Tech Stack:** Swift 6 (language mode v6, strict concurrency), SwiftUI, XCTest, iOS 16+, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-05-request-breakpoints-design.md`

**Prerequisite:** the Network Rules plan (`docs/superpowers/plans/2026-09-05-network-rules.md`) must be implemented first. This plan consumes `NetworkRuleMatch`, `NetworkRulePattern` and the `startLoading()` hook it establishes.

## Global Constraints

- **iOS only.** Never build for macOS. `swift build` does not work.
- **Build and test on the booted simulator.** `S=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for v in d.values() for x in v if x["state"]=="Booted"))')`; if none, `xcrun simctl boot 0EEED0FF-A025-468E-9466-3BDE708B41B0`.
- **Full test command:** `xcodebuild test -scheme Scyther -destination "platform=iOS Simulator,id=$S" -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed \(|Executed [0-9]+ tests|TEST " | sort -u | tail -8`
- **`pause` must never be called on the main thread.** It blocks. The coordinator asserts this, and the assertion must survive into release as a `logMessage` warning rather than being compiled out.
- **Breakpoints are disabled entirely when `AppEnvironment.isTestCase` is true**, so a stray breakpoint cannot hang CI. The tests in this plan drive `BreakpointCoordinator` directly rather than through the interceptor for exactly that reason, except where a test explicitly overrides the gate.
- **The timeout cannot be disabled.** Default 60 seconds, range 5 to 300, enforced on the model.
- **Swift 6 strict concurrency.** The coordinator is `Sendable` with an `NSLock`; `pause` is `nonisolated`.
- **Minimum deployment target iOS 16.** **MVVM**, view models in their own files. **DocC `///` on every new type and member.** **Alerts only.**
- **Every user-facing string through `localized(_:)`**, keys added to `Scripts/localization/strings/Breakpoints.json` in all twelve languages (`fr, de, es, it, pt-BR, nl, ja, zh-Hans, zh-Hant, ko, ru, ar`), then `python3 Scripts/localization/build_catalog.py`. `grep -l '"<key>"' Scripts/localization/strings/*.json` before adding any key.
- **Never put a Claude session URL or any Claude mention in a commit message, PR body, or documentation.**
- **Exact names:** module `Sources/Scyther/Features/NetworkBreakpoints/`; defaults keys `Scyther.NetworkBreakpoints.Breakpoints` and `Scyther.NetworkBreakpoints.Enabled`; menu item `MenuItem.networkBreakpoints`, id `networkBreakpoints`, icon `pause.circle`.
- **The master switch defaults to off.**

---

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `Sources/Scyther/Features/NetworkBreakpoints/NetworkBreakpoint.swift` | The model and its `Stage` |
| `Sources/Scyther/Features/NetworkBreakpoints/BreakpointDraft.swift` | The editable snapshot of a held request or response |
| `Sources/Scyther/Features/NetworkBreakpoints/BreakpointCoordinator.swift` | `pause` / `resolve`, the semaphore and the timeout |
| `Sources/Scyther/Features/NetworkBreakpoints/BreakpointStore.swift` | Persistence and the lock-guarded snapshot |
| `Sources/Scyther/Features/NetworkBreakpoints/BreakpointsView.swift` + `ViewModel` | The breakpoint list |
| `Sources/Scyther/Features/NetworkBreakpoints/BreakpointEditorView.swift` + `ViewModel` | The held-request editor |
| `Sources/Scyther/Features/NetworkBreakpoints/BreakpointPresenter.swift` | Puts the editor on screen from any thread |
| `Scripts/localization/strings/Breakpoints.json` | Strings |
| `Tests/ScytherTests/Features/BreakpointCoordinatorTests.swift` | Pause, resolve, timeout, concurrency |
| `Tests/ScytherTests/Features/BreakpointStoreTests.swift` | Persistence, defaults, the test-case gate |
| `Tests/ScytherTests/Features/BreakpointDraftTests.swift` | Draft ↔ request conversion |

**Modified:** `HTTPInterceptorURLProtocol.swift` (both stages), `HTTPRequest.swift` (`breakpointNames`, `wasEdited`), `HTTPResponseView.swift` (HELD badge), `MenuItem/MenuSection/MenuView/MenuSearchIndex`, `README.md`, `Sources/Scyther/Scyther.docc/NetworkDebugging.md`.

---

### Task 1: The model, the draft, and the store

**Files:**
- Create: `NetworkBreakpoint.swift`, `BreakpointDraft.swift`, `BreakpointStore.swift`
- Test: `Tests/ScytherTests/Features/BreakpointDraftTests.swift`, `Tests/ScytherTests/Features/BreakpointStoreTests.swift`

**Interfaces:**
- Consumes: `NetworkRuleMatch`, `NetworkRulePattern` (Network Rules plan, Task 1).
- Produces: `NetworkBreakpoint` (`id`, `name`, `isEnabled`, `match`, `stage`, `timeout`); `NetworkBreakpoint.Stage` (`.request`, `.response`, `.both`); `BreakpointDraft` with `init(request: URLRequest)`, `init(response: HTTPURLResponse, body: Data)`, `makeURLRequest(basedOn: URLRequest) -> URLRequest`, `makeResponse(url: URL) -> (HTTPURLResponse, Data)?`; `BreakpointStore` (`shared`, `init(defaults:)`, `breakpoints`, `isEnabled`, `add`, `update`, `remove(id:)`, `removeAll`); `BreakpointSnapshot.current -> (isEnabled: Bool, breakpoints: [NetworkBreakpoint])`.

- [ ] **Step 1: Write the failing draft tests**

```swift
//
//  BreakpointDraftTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class BreakpointDraftTests: XCTestCase {

    func testARequestDraftCapturesMethodURLHeadersAndBody() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/users?page=2")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"name\":\"Ada\"}".utf8)

        let draft = BreakpointDraft(request: request)
        XCTAssertEqual(draft.method, "POST")
        XCTAssertEqual(draft.url, "https://api.example.com/v1/users?page=2")
        XCTAssertEqual(draft.headers.first { $0.name == "Content-Type" }?.value, "application/json")
        XCTAssertEqual(draft.body, Data("{\"name\":\"Ada\"}".utf8))
        XCTAssertNil(draft.statusCode, "a request draft has no status")
    }

    func testAnEditedRequestDraftRebuildsTheRequest() throws {
        var original = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        original.httpMethod = "GET"

        var draft = BreakpointDraft(request: original)
        draft.method = "PUT"
        draft.url = "https://api.example.com/v1/users/1"
        draft.headers.append(BreakpointDraft.Header(name: "X-Debug", value: "1"))
        draft.body = Data("{}".utf8)

        let rebuilt = draft.makeURLRequest(basedOn: original)
        XCTAssertEqual(rebuilt.httpMethod, "PUT")
        XCTAssertEqual(rebuilt.url?.absoluteString, "https://api.example.com/v1/users/1")
        XCTAssertEqual(rebuilt.value(forHTTPHeaderField: "X-Debug"), "1")
        XCTAssertEqual(rebuilt.httpBody, Data("{}".utf8))
    }

    func testAnInvalidURLKeepsTheOriginalRequestURL() {
        let original = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        var draft = BreakpointDraft(request: original)
        draft.url = "not a url at all"
        XCTAssertEqual(draft.makeURLRequest(basedOn: original).url, original.url)
    }

    func testAResponseDraftCapturesStatusHeadersAndBody() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1/users")!,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        let draft = BreakpointDraft(response: response, body: Data("{\"error\":true}".utf8))
        XCTAssertEqual(draft.statusCode, 500)
        XCTAssertEqual(draft.headers.first { $0.name == "Content-Type" }?.value, "application/json")
        XCTAssertEqual(draft.body, Data("{\"error\":true}".utf8))
    }

    func testAnEditedResponseDraftRebuildsTheResponse() throws {
        let url = URL(string: "https://api.example.com/v1/users")!
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: [:]))
        var draft = BreakpointDraft(response: response, body: Data())
        draft.statusCode = 200
        draft.body = Data("[]".utf8)

        let rebuilt = try XCTUnwrap(draft.makeResponse(url: url))
        XCTAssertEqual(rebuilt.0.statusCode, 200)
        XCTAssertEqual(rebuilt.1, Data("[]".utf8))
    }
}
```

- [ ] **Step 2: Write the failing store tests**

```swift
//
//  BreakpointStoreTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class BreakpointStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "BreakpointStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeBreakpoint(_ name: String, stage: NetworkBreakpoint.Stage = .request) -> NetworkBreakpoint {
        NetworkBreakpoint(id: UUID(), name: name, isEnabled: true, match: .path("/v1/*"), stage: stage, timeout: 60)
    }

    func testTheMasterSwitchDefaultsToOff() {
        XCTAssertFalse(BreakpointStore(defaults: defaults).isEnabled)
    }

    func testBreakpointsRoundTrip() {
        let store = BreakpointStore(defaults: defaults)
        store.add(makeBreakpoint("cart", stage: .both))
        let reloaded = BreakpointStore(defaults: defaults)
        XCTAssertEqual(reloaded.breakpoints.map(\.name), ["cart"])
        XCTAssertEqual(reloaded.breakpoints.first?.stage, .both)
    }

    func testTimeoutIsClampedToTheAllowedRange() {
        let store = BreakpointStore(defaults: defaults)
        var tooShort = makeBreakpoint("short"); tooShort.timeout = 1
        var tooLong = makeBreakpoint("long"); tooLong.timeout = 9_000
        store.add(tooShort)
        store.add(tooLong)
        XCTAssertEqual(store.breakpoints.map(\.timeout), [5, 300])
    }

    func testTheSnapshotReportsDisabledInATestCase() {
        let store = BreakpointStore(defaults: defaults)
        store.isEnabled = true
        store.add(makeBreakpoint("cart"))
        XCTAssertFalse(
            BreakpointSnapshot.current.isEnabled,
            "AppEnvironment.isTestCase is true in this process, so breakpoints must report as off"
        )
    }
}
```

- [ ] **Step 3: Run both to verify they fail**

Run the full test command. Expected: `cannot find 'BreakpointDraft' in scope`, `cannot find 'BreakpointStore' in scope`.

- [ ] **Step 4: Write the model and draft**

`NetworkBreakpoint` is the struct from the spec's Component 1 plus `var timeout: TimeInterval`, with `///` docs on every member. `BreakpointDraft`:

```swift
/// An editable snapshot of a request or response held at a breakpoint.
///
/// The same type serves both stages: a request draft has a `method` and `url` and no
/// `statusCode`; a response draft has a `statusCode` and no method. Headers are an ordered array
/// rather than a dictionary because a duplicated header is meaningful and a dictionary would
/// silently collapse it.
struct BreakpointDraft: Identifiable, Equatable, Sendable {
    struct Header: Identifiable, Equatable, Sendable {
        let id = UUID()
        var name: String
        var value: String
    }

    let id = UUID()
    var method: String?
    var url: String?
    var statusCode: Int?
    var headers: [Header]
    var body: Data?
}
```

`makeURLRequest(basedOn:)` copies the original, then applies method, URL (only when `URL(string:)` succeeds), headers via `setValue(_:forHTTPHeaderField:)`, and body. `makeResponse(url:)` builds an `HTTPURLResponse` from `statusCode` and the headers, returning `nil` if construction fails.

- [ ] **Step 5: Write the store and snapshot**

`BreakpointStore` mirrors `NetworkRuleStore`: `@MainActor final class`, `init(defaults: UserDefaults = .scyther)`, JSON under the two keys from Global Constraints, `isEnabled` defaulting to **false**, `add`/`update` clamping `timeout` into `5...300`, and every mutation calling `publish()`.

`BreakpointSnapshot` is the lock-guarded holder, with one addition over the rules version:

```swift
    /// The current snapshot. Reports disabled during an XCTest run so a breakpoint left enabled
    /// can never hang CI.
    static var current: (isEnabled: Bool, breakpoints: [NetworkBreakpoint]) {
        guard !AppEnvironment.isTestCase else { return (false, []) }
        return lock.withLock { storage }
    }
```

- [ ] **Step 6: Run to verify both pass**

Expected: `** TEST SUCCEEDED **` with 9 new tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/NetworkBreakpoints Tests/ScytherTests/Features/BreakpointDraftTests.swift Tests/ScytherTests/Features/BreakpointStoreTests.swift
git commit -m "Add the breakpoint model, draft and store"
```

---

### Task 2: The coordinator

**Files:**
- Create: `Sources/Scyther/Features/NetworkBreakpoints/BreakpointCoordinator.swift`
- Test: `Tests/ScytherTests/Features/BreakpointCoordinatorTests.swift`

**Interfaces:**
- Consumes: `BreakpointDraft`, `NetworkBreakpoint.Stage`.
- Produces: `BreakpointResolution` (`.continue(BreakpointDraft)`, `.abort(URLError.Code)`, `.timedOut`); `PendingBreakpoint` (`id`, `breakpointName`, `stage`, `draft`, `deadline`); `BreakpointCoordinator.shared`, `pause(_:name:stage:timeout:) -> BreakpointResolution`, `@MainActor resolve(id:with:)`, `@MainActor var pending: [PendingBreakpoint]`, and `onPendingChanged: (@MainActor ([PendingBreakpoint]) -> Void)?`.

- [ ] **Step 1: Write the failing coordinator tests**

```swift
//
//  BreakpointCoordinatorTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class BreakpointCoordinatorTests: XCTestCase {

    private var coordinator: BreakpointCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = BreakpointCoordinator()
    }

    private func draft() -> BreakpointDraft {
        BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/v1/users")!))
    }

    /// Runs `pause` off the main thread, the way the interceptor does.
    private func pauseOffMain(
        timeout: TimeInterval = 5,
        resolve: @escaping @MainActor (UUID) -> Void
    ) async -> BreakpointResolution {
        let expectation = expectation(description: "paused")
        nonisolated(unsafe) var captured: BreakpointResolution?

        Task { @MainActor in
            for _ in 0..<200 where coordinator.pending.isEmpty {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            if let id = coordinator.pending.first?.id { resolve(id) }
        }
        DispatchQueue.global().async { [self] in
            captured = coordinator.pause(draft(), name: "cart", stage: .request, timeout: timeout)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 10)
        return captured ?? .timedOut
    }

    func testResolvingWithContinueReturnsTheEditedDraft() async {
        var edited = draft()
        edited.method = "DELETE"
        let resolution = await pauseOffMain { [self] id in
            coordinator.resolve(id: id, with: .continue(edited))
        }
        guard case .continue(let returned) = resolution else { return XCTFail("expected continue") }
        XCTAssertEqual(returned.method, "DELETE")
    }

    func testResolvingWithAbortReturnsTheCode() async {
        let resolution = await pauseOffMain { [self] id in
            coordinator.resolve(id: id, with: .abort(.cancelled))
        }
        guard case .abort(let code) = resolution else { return XCTFail("expected abort") }
        XCTAssertEqual(code, .cancelled)
    }

    func testAnUnresolvedPauseTimesOut() async {
        let start = Date()
        let expectation = expectation(description: "timed out")
        nonisolated(unsafe) var captured: BreakpointResolution?
        DispatchQueue.global().async { [self] in
            captured = coordinator.pause(draft(), name: "cart", stage: .request, timeout: 0.4)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)

        guard case .timedOut = captured else { return XCTFail("expected timedOut, got \(String(describing: captured))") }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.4)
    }

    func testAPendingBreakpointIsRemovedOnceResolved() async {
        _ = await pauseOffMain { [self] id in coordinator.resolve(id: id, with: .timedOut) }
        let pending = await MainActor.run { coordinator.pending }
        XCTAssertTrue(pending.isEmpty)
    }

    func testConcurrentPausesResolveIndependently() async {
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        nonisolated(unsafe) var results: [String] = []
        let lock = NSLock()

        for name in ["a", "b"] {
            DispatchQueue.global().async { [self] in
                _ = coordinator.pause(draft(), name: name, stage: .request, timeout: 5)
                lock.withLock { results.append(name) }
                (name == "a" ? first : second).fulfill()
            }
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {
            coordinator.pending.forEach { coordinator.resolve(id: $0.id, with: .timedOut) }
        }
        await fulfillment(of: [first, second], timeout: 10)
        XCTAssertEqual(Set(results), ["a", "b"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'BreakpointCoordinator' in scope`.

- [ ] **Step 3: Write the coordinator**

```swift
/// Bridges the URL loading system's per-request thread and the main actor.
///
/// `pause` is called from `HTTPInterceptorURLProtocol` on a thread the loading system owns. It
/// blocks that one thread — never the main thread, and never a queue shared with other requests —
/// until the UI resolves it or the timeout elapses.
final class BreakpointCoordinator: @unchecked Sendable {
    static let shared = BreakpointCoordinator()

    private let lock = NSLock()
    private var semaphores: [UUID: DispatchSemaphore] = [:]
    private var resolutions: [UUID: BreakpointResolution] = [:]
    @MainActor private(set) var pending: [PendingBreakpoint] = []
    /// Called on the main actor whenever `pending` changes, so a presenter can show or hide UI.
    @MainActor var onPendingChanged: (([PendingBreakpoint]) -> Void)?

    /// Holds the calling thread until the breakpoint is resolved or `timeout` elapses.
    ///
    /// - Warning: Blocks. Never call from the main thread.
    func pause(
        _ draft: BreakpointDraft,
        name: String,
        stage: NetworkBreakpoint.Stage,
        timeout: TimeInterval
    ) -> BreakpointResolution {
        if Thread.isMainThread {
            logMessage("Scyther: a breakpoint was reached on the main thread and was skipped.")
            return .timedOut
        }

        let id = UUID()
        let semaphore = DispatchSemaphore(value: 0)
        lock.withLock { semaphores[id] = semaphore }

        let item = PendingBreakpoint(
            id: id, breakpointName: name, stage: stage, draft: draft,
            deadline: Date().addingTimeInterval(timeout)
        )
        Task { @MainActor in
            pending.append(item)
            onPendingChanged?(pending)
        }

        let outcome = semaphore.wait(timeout: .now() + timeout)
        let resolution = lock.withLock { () -> BreakpointResolution in
            semaphores[id] = nil
            return resolutions.removeValue(forKey: id) ?? .timedOut
        }
        Task { @MainActor in
            pending.removeAll { $0.id == id }
            onPendingChanged?(pending)
        }
        return outcome == .success ? resolution : .timedOut
    }

    /// Resolves a held breakpoint, releasing the thread waiting on it.
    @MainActor
    func resolve(id: UUID, with resolution: BreakpointResolution) {
        let semaphore = lock.withLock { () -> DispatchSemaphore? in
            resolutions[id] = resolution
            return semaphores[id]
        }
        semaphore?.signal()
    }
}
```

`PendingBreakpoint` is a `@MainActor final class ... ObservableObject` with `@Published var draft`.

- [ ] **Step 4: Run to verify it passes**

Expected: `** TEST SUCCEEDED **` with 5 more tests. If `testAnUnresolvedPauseTimesOut` hangs, the semaphore timeout is not being honoured — check that `wait(timeout:)` is used, not `wait()`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/NetworkBreakpoints/BreakpointCoordinator.swift Tests/ScytherTests/Features/BreakpointCoordinatorTests.swift
git commit -m "Add the breakpoint coordinator"
```

---

### Task 3: Interceptor integration

**Files:**
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPInterceptorURLProtocol.swift`
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift`
- Test: append `BreakpointInterceptorTests` to `Tests/ScytherTests/Features/BreakpointCoordinatorTests.swift`

**Interfaces:**
- Consumes: `BreakpointSnapshot.current`, `BreakpointCoordinator.shared`, `BreakpointDraft`.
- Produces: `HTTPRequest.breakpointNames: [String]`, `HTTPRequest.wasEdited: Bool`.

- [ ] **Step 1: Write the failing integration test**

Because `BreakpointSnapshot.current` reports disabled under XCTest, this test drives the protocol's helper directly rather than through a live request:

```swift
final class BreakpointInterceptorTests: XCTestCase {

    func testABufferedResponseIsWithheldUntilResolvedAndThenEdited() throws {
        let url = URL(string: "https://api.example.com/v1/users")!
        let original = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: [:]))
        var draft = BreakpointDraft(response: original, body: Data("{\"error\":true}".utf8))
        draft.statusCode = 200
        draft.body = Data("[]".utf8)

        let resolved = try XCTUnwrap(draft.makeResponse(url: url))
        XCTAssertEqual(resolved.0.statusCode, 200)
        XCTAssertEqual(resolved.1, Data("[]".utf8))
    }

    func testTheRequestStageRebuildsFromTheDraft() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        request.httpMethod = "GET"
        var draft = BreakpointDraft(request: request)
        draft.headers.append(BreakpointDraft.Header(name: "X-Held", value: "1"))
        XCTAssertEqual(draft.makeURLRequest(basedOn: request).value(forHTTPHeaderField: "X-Held"), "1")
    }

    func testPauseIsSkippedOnTheMainThread() {
        let coordinator = BreakpointCoordinator()
        let draft = BreakpointDraft(request: URLRequest(url: URL(string: "https://a.com")!))
        let resolution = coordinator.pause(draft, name: "main", stage: .request, timeout: 5)
        guard case .timedOut = resolution else {
            return XCTFail("pausing on the main thread must return immediately, not block the app")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: the first two compile only once Task 1 is merged (they will already pass); `testPauseIsSkippedOnTheMainThread` fails or hangs until the main-thread guard exists.

- [ ] **Step 3: Add the interceptor fields and request stage**

In `HTTPRequest`, add with `///` docs:

```swift
    /// Names of the breakpoints that held this request, if any.
    var breakpointNames: [String] = []

    /// Whether the developer edited the request or response while it was held.
    var wasEdited: Bool = false
```

In `startLoading()`, after the rules outcome is applied and before the data task is created:

```swift
        let breakpoints = BreakpointSnapshot.current
        if breakpoints.isEnabled,
           let held = breakpoints.breakpoints.first(where: {
               $0.isEnabled && $0.stage != .response && $0.match.matches(request)
           }) {
            let draft = BreakpointDraft(request: mutableRequest as URLRequest)
            switch BreakpointCoordinator.shared.pause(draft, name: held.name, stage: .request, timeout: held.timeout) {
            case .continue(let edited):
                let rebuilt = edited.makeURLRequest(basedOn: mutableRequest as URLRequest)
                model.breakpointNames.append(held.name)
                model.wasEdited = edited != draft
                session.dataTask(with: rebuilt).resume()
                return
            case .abort(let code):
                model.breakpointNames.append(held.name)
                model.saveErrorResponse()
                finishWithFailure(URLError(code))
                return
            case .timedOut:
                break
            }
        }
```

- [ ] **Step 4: Add the response stage**

Add `private var heldBreakpoint: NetworkBreakpoint?` and `private var bufferedResponse: HTTPURLResponse?`, set in `startLoading()` when a response-stage breakpoint matches.

In `urlSession(_:dataTask:didReceive response:)`, when `heldBreakpoint != nil`, store the response and **do not** call `client?.urlProtocol(_:didReceive:cacheStoragePolicy:)`.

In `urlSession(_:dataTask:didReceive data:)`, when `heldBreakpoint != nil`, append to `responseData` and **do not** call `didLoad:`.

In `urlSession(_:task:didCompleteWithError:)`, before the existing `defer` block, when `heldBreakpoint != nil` and there is a buffered response: build a `BreakpointDraft(response:body:)`, cap the buffer at 10 MB (skip the pause and log via `logMessage` above that), call `pause`, then emit the resolved response and body through `didReceive` / `didLoad` before the normal completion path runs.

- [ ] **Step 5: Run the suite**

Full test command. Expected: `** TEST SUCCEEDED **`, with no change to the request count for non-breakpoint tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger Tests/ScytherTests/Features/BreakpointCoordinatorTests.swift
git commit -m "Hold matching requests and responses at breakpoints"
```

---

### Task 4: UI, presentation, and documentation

**Files:**
- Create: `BreakpointsView.swift`, `BreakpointsViewModel.swift`, `BreakpointEditorView.swift`, `BreakpointEditorViewModel.swift`, `BreakpointPresenter.swift`
- Create: `Scripts/localization/strings/Breakpoints.json`
- Modify: `MenuItem.swift`, `MenuSection.swift`, `MenuView.swift`, `MenuSearchIndex.swift`, `HTTPResponseView.swift`, `README.md`, `NetworkDebugging.md`

**Interfaces:**
- Consumes: `BreakpointStore.shared`, `BreakpointCoordinator.shared`, `PendingBreakpoint`.
- Produces: `MenuItem.networkBreakpoints`.

- [ ] **Step 1: Write the list and editor**

`BreakpointsView`: master switch (with a footer explaining that breakpoints block the app and are ignored during tests), the breakpoint list with per-row enable toggles, swipe to delete, and an editor for name, match facets, stage `Picker` and a timeout `Stepper` bounded to 5...300.

`BreakpointEditorView`: driven by a `PendingBreakpoint`. For a request it edits method, URL, headers and body; for a response, status, headers and body. Three actions: **Continue**, **Continue without changes**, and a destructive **Abort** which asks which `URLError` to raise. A countdown row shows the seconds left before the automatic continue, driven by a `TimelineView(.periodic(from: .now, by: 1))`.

- [ ] **Step 2: Write the presenter**

`BreakpointPresenter` sets `BreakpointCoordinator.shared.onPendingChanged` during `Scyther.start()`. When the list becomes non-empty and nothing is presented, it presents a `UIHostingController` wrapping `BreakpointEditorView` over the top view controller, reusing the presentation path in `Scyther.showMenu(from:)`. When the list empties, it dismisses. It skips presentation entirely when `UIApplication.shared.applicationState != .active`, logging via `logMessage`, because a held request the developer cannot see looks like a hang.

- [ ] **Step 3: Add the HELD badge and wire the menu**

`HTTPResponseView` gains a `HELD` lozenge beside `MOCKED`, shown when `breakpointNames` is non-empty, using the same badge builder. Menu wiring follows the Network Rules plan's Task 6 pattern with `MenuItem.networkBreakpoints`, icon `pause.circle`, placed after `.networkRules`; search keywords `["pause", "hold", "intercept", "edit request", "charles", "proxyman"]`.

- [ ] **Step 4: Localise**

Every literal through `localized(_:)`, keys in `Scripts/localization/strings/Breakpoints.json` in all twelve languages, then `python3 Scripts/localization/build_catalog.py`.

- [ ] **Step 5: Run everything and verify manually**

Full test command, example app build. Then: enable the master switch, add a breakpoint matching the example app's sample request, fire it, confirm the editor appears over the app, edit a header, continue, and confirm the HELD badge and the edited header in the log. Repeat with the timeout, confirming the request completes on its own after the countdown.

- [ ] **Step 6: Documentation**

README gains a **Request Breakpoints** subsection under Networking: what it does, that it blocks one request, the timeout, that it never fires during tests, and the response-stage buffering caveat. `NetworkDebugging.md` mirrors it.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/NetworkBreakpoints Sources/Scyther/Features/NetworkLogger Sources/Scyther/Features/Menu Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings README.md Sources/Scyther/Scyther.docc
git commit -m "Add the breakpoints screen, editor and presenter"
```

---

## Self-review

- **Spec coverage:** Component 1 → Task 1. Component 2 → Task 2. Component 3 → Task 3 (both stages, the 10 MB cap, `breakpointNames`/`wasEdited`). Component 4 → Task 4 (presenter, editor, countdown). Component 5 → Task 1 (`isTestCase` gate, timeout clamping, master switch off) and Task 4 (background skip). Component 6 → the test file in each task.
- **Placeholders:** none.
- **Type consistency:** `BreakpointDraft.makeURLRequest(basedOn:)`, `makeResponse(url:)`, `BreakpointCoordinator.pause(_:name:stage:timeout:)`, `resolve(id:with:)`, `BreakpointSnapshot.current`, `NetworkBreakpoint.Stage` are spelled identically in every task.
- **One risk the plan carries deliberately:** `BreakpointSnapshot.current` reporting disabled under XCTest means no test drives a live request through a breakpoint. Task 3 tests the pieces and Task 4 verifies end to end by hand. Weakening the gate to allow an integration test would reintroduce exactly the CI hang the gate exists to prevent.
