# Request Replay and Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From a captured request's detail page, open an editor pre-filled with that request, change it, send it again, and see the new response in the log linked to the original.

**Architecture:** A pure `ReplayableRequest` converts a captured `HTTPRequest` into an editable draft and back into a `URLRequest`, stamping a `URLProtocol` property that carries provenance. The replay is fired through a plain `URLSession` and captured by the existing interceptor like any other app request — the only capture-side change is three lines reading that property. A pure `ReplayComparison` computes the deltas the detail page shows.

**Tech Stack:** Swift 6 (language mode v6, strict concurrency), SwiftUI, XCTest, iOS 16+, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-05-request-replay-design.md`

**Prerequisite:** none. This plan is independent of the Network Rules and Breakpoints work and can be implemented before, after, or alongside them. The one point of contact: if Network Rules is already merged, Task 3's Replay button must be hidden when `request.wasStubbed` is true.

## Global Constraints

- **iOS only.** Never build for macOS. `swift build` does not work.
- **Build and test on the booted simulator.** `S=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for v in d.values() for x in v if x["state"]=="Booted"))')`; if none, `xcrun simctl boot 0EEED0FF-A025-468E-9466-3BDE708B41B0`.
- **Full test command:** `xcodebuild test -scheme Scyther -destination "platform=iOS Simulator,id=$S" -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed \(|Executed [0-9]+ tests|TEST " | sort -u | tail -8`
- **Header order is preserved.** Headers are an ordered array of name/value pairs, never a dictionary: a duplicated header is meaningful and a dictionary silently collapses it.
- **Swift 6 strict concurrency.** `ReplayableRequest` and `ReplayComparison` are `Sendable` value types with no global state.
- **Minimum deployment target iOS 16.** **MVVM**, view models in their own files. **DocC `///` on every new type and member.** **Alerts only, never `.confirmationDialog`.**
- **Every user-facing string through `localized(_:)`**, keys added to the existing `Scripts/localization/strings/NetworkLogger.json` (which already owns the detail page's copy) in all twelve languages (`fr, de, es, it, pt-BR, nl, ja, zh-Hans, zh-Hant, ko, ru, ar`), then `python3 Scripts/localization/build_catalog.py`. `grep -l '"<key>"' Scripts/localization/strings/*.json` before adding any key.
- **Never put a Claude session URL or any Claude mention in a commit message, PR body, or documentation.**
- **Exact names:** module `Sources/Scyther/Features/RequestReplay/`; the `URLProtocol` property key constant is `internal let replayOfRequestKey = "Scyther_Replay_Of_Request"`, declared beside `internalNetworkRequestKey` in `HTTPInterceptorURLProtocol.swift`.

---

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `Sources/Scyther/Features/RequestReplay/ReplayableRequest.swift` | Capture → draft → `URLRequest` |
| `Sources/Scyther/Features/RequestReplay/ReplayComparison.swift` | Status, duration and size deltas |
| `Sources/Scyther/Features/RequestReplay/ReplayEditorView.swift` | The editor sheet |
| `Sources/Scyther/Features/RequestReplay/ReplayEditorViewModel.swift` | Validation and sending |
| `Tests/ScytherTests/Features/ReplayableRequestTests.swift` | Draft conversion |
| `Tests/ScytherTests/Features/ReplayComparisonTests.swift` | Deltas |
| `Tests/ScytherTests/Features/ReplayEditorViewModelTests.swift` | Validation, header editing |

**Modified:** `HTTPRequest.swift` (`replayOfID`), `HTTPInterceptorURLProtocol.swift` (read the property), `HTTPResponseView.swift` (REPLAY badge), `LogDetailsView.swift` / `LogDetailsViewModel.swift` (Replay button, Replays section, Original row), `NetworkLogsViewModel.swift` (look up related requests), `README.md`, `Sources/Scyther/Scyther.docc/NetworkDebugging.md`.

---

### Task 1: `ReplayableRequest` and `ReplayComparison`

**Files:**
- Create: `Sources/Scyther/Features/RequestReplay/ReplayableRequest.swift`
- Create: `Sources/Scyther/Features/RequestReplay/ReplayComparison.swift`
- Test: `Tests/ScytherTests/Features/ReplayableRequestTests.swift`, `Tests/ScytherTests/Features/ReplayComparisonTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest` (`requestURL`, `requestMethod`, `requestHeaders`, `getRequestBodyFilepath()`, `readRawData(_:)`, `getRandomHash()`, `responseCode`, `requestDuration`, `responseBodyLength`).
- Produces: `ReplayableRequest` (`method`, `url`, `headers: [Header]`, `body`, `init(capturing:)`, `makeURLRequest(replayOf:) -> URLRequest?`, `isModified(from:) -> Bool`, `static let managedHeaderNames: Set<String>`); `ReplayableRequest.Header` (`id`, `name`, `value`); `ReplayComparison` (`init(original:replay:)`, `statusChanged`, `durationDeltaMilliseconds`, `sizeDeltaBytes`).

- [ ] **Step 1: Write the failing draft tests**

```swift
//
//  ReplayableRequestTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class ReplayableRequestTests: XCTestCase {

    /// Builds a captured model the way the interceptor does, including a body on disk.
    private func capture(
        url: String = "https://api.example.com/v1/users?page=2",
        method: String = "POST",
        headers: [String: String] = ["Content-Type": "application/json", "Authorization": "Bearer abc"],
        body: String? = "{\"name\":\"Ada\"}"
    ) -> HTTPRequest {
        let mutable = NSMutableURLRequest(url: URL(string: url)!)
        mutable.httpMethod = method
        headers.forEach { mutable.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            // The same mechanism the interceptor uses to hand a body to the logger.
            URLProtocol.setProperty(Data(body.utf8), forKey: "ScytherBodyData", in: mutable)
        }
        let request = mutable as URLRequest
        let model = HTTPRequest()
        model.saveRequest(request)
        model.saveRequestBody(request)
        return model
    }

    func testADraftCapturesMethodURLHeadersAndBody() {
        let draft = ReplayableRequest(capturing: capture())
        XCTAssertEqual(draft.method, "POST")
        XCTAssertEqual(draft.url, "https://api.example.com/v1/users?page=2")
        XCTAssertEqual(draft.headers.first { $0.name == "Authorization" }?.value, "Bearer abc")
        XCTAssertEqual(draft.body, Data("{\"name\":\"Ada\"}".utf8))
    }

    func testHeadersKeepTheirOrderAndDuplicates() {
        var draft = ReplayableRequest(capturing: capture(headers: [:], body: nil))
        draft.headers = [
            .init(name: "Accept", value: "application/json"),
            .init(name: "Accept", value: "text/plain"),
        ]
        let request = draft.makeURLRequest(replayOf: "abc")
        XCTAssertEqual(draft.headers.map(\.value), ["application/json", "text/plain"])
        XCTAssertNotNil(request, "a duplicated header must not prevent the request being built")
    }

    func testMakeURLRequestStampsProvenance() throws {
        let draft = ReplayableRequest(capturing: capture())
        let request = try XCTUnwrap(draft.makeURLRequest(replayOf: "original-hash"))
        XCTAssertEqual(URLProtocol.property(forKey: replayOfRequestKey, in: request) as? String, "original-hash")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, Data("{\"name\":\"Ada\"}".utf8))
    }

    func testMakeURLRequestReturnsNilForAnInvalidURL() {
        var draft = ReplayableRequest(capturing: capture())
        draft.url = "not a url"
        XCTAssertNil(draft.makeURLRequest(replayOf: "abc"))
    }

    func testIsModifiedDetectsEachEditedFacet() {
        let original = ReplayableRequest(capturing: capture())
        XCTAssertFalse(original.isModified(from: original))

        var method = original; method.method = "PUT"
        XCTAssertTrue(method.isModified(from: original))

        var url = original; url.url = "https://api.example.com/v1/users/1"
        XCTAssertTrue(url.isModified(from: original))

        var header = original; header.headers.append(.init(name: "X-Debug", value: "1"))
        XCTAssertTrue(header.isModified(from: original))

        var body = original; body.body = Data("{}".utf8)
        XCTAssertTrue(body.isModified(from: original))
    }

    func testManagedHeadersAreNamed() {
        XCTAssertTrue(ReplayableRequest.managedHeaderNames.contains("content-length"))
        XCTAssertTrue(ReplayableRequest.managedHeaderNames.contains("host"))
    }
}
```

- [ ] **Step 2: Write the failing comparison tests**

```swift
//
//  ReplayComparisonTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class ReplayComparisonTests: XCTestCase {

    private func model(status: Int?, duration: Float?, size: Int?) -> HTTPRequest {
        let request = HTTPRequest()
        request.responseCode = status
        request.requestDuration = duration
        request.responseBodyLength = size
        request.noResponse = status == nil
        return request
    }

    func testIdenticalResponsesReportNoChange() {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 100, size: 500),
            replay: model(status: 200, duration: 100, size: 500)
        )
        XCTAssertFalse(comparison.statusChanged)
        XCTAssertEqual(comparison.durationDeltaMilliseconds, 0)
        XCTAssertEqual(comparison.sizeDeltaBytes, 0)
    }

    func testAChangedStatusIsReported() {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 100, size: 500),
            replay: model(status: 401, duration: 90, size: 40)
        )
        XCTAssertTrue(comparison.statusChanged)
        XCTAssertEqual(comparison.durationDeltaMilliseconds, -10)
        XCTAssertEqual(comparison.sizeDeltaBytes, -460)
    }

    func testAPendingReplayHasNoDeltas() {
        let comparison = ReplayComparison(
            original: model(status: 200, duration: 100, size: 500),
            replay: model(status: nil, duration: nil, size: nil)
        )
        XCTAssertNil(comparison.durationDeltaMilliseconds)
        XCTAssertNil(comparison.sizeDeltaBytes)
        XCTAssertTrue(comparison.statusChanged, "no response is a change from a 200")
    }
}
```

- [ ] **Step 3: Run both to verify they fail**

Run the full test command. Expected: `cannot find 'ReplayableRequest' in scope`, `cannot find 'replayOfRequestKey' in scope`.

- [ ] **Step 4: Declare the provenance key**

In `HTTPInterceptorURLProtocol.swift`, beside `internalNetworkRequestKey`:

```swift
/// Property key carrying the hash of the request a replay was built from.
internal let replayOfRequestKey = "Scyther_Replay_Of_Request"
```

- [ ] **Step 5: Write `ReplayableRequest`**

```swift
/// An editable copy of a captured request, and the bridge back to a live `URLRequest`.
///
/// Headers are an ordered array rather than a dictionary because a duplicated header
/// (`Accept`, `Set-Cookie`) is meaningful, and a dictionary would silently collapse it.
struct ReplayableRequest: Equatable, Sendable {
    struct Header: Identifiable, Equatable, Sendable {
        let id = UUID()
        var name: String
        var value: String

        static func == (lhs: Header, rhs: Header) -> Bool {
            lhs.name == rhs.name && lhs.value == rhs.value
        }
    }

    var method: String
    var url: String
    var headers: [Header]
    var body: Data?

    /// Headers `URLSession` sets itself. Editing them has no effect, so the UI marks them managed.
    static let managedHeaderNames: Set<String> = ["content-length", "host", "connection"]

    /// Builds a draft from a captured request, reading its body from disk.
    init(capturing request: HTTPRequest) {
        method = request.requestMethod ?? "GET"
        url = request.requestURL ?? ""
        headers = (request.requestHeaders ?? [:])
            .compactMap { key, value in
                guard let name = key as? String else { return nil }
                return Header(name: name, value: "\(value)")
            }
            .sorted { $0.name < $1.name }
        let data = request.readRawData(request.getRequestBodyFilepath())
        body = (data?.isEmpty == false) ? data : nil
    }

    /// Builds the outgoing request, stamped with the hash of the request it replays.
    ///
    /// - Parameter originalID: The original's `getRandomHash()` value.
    /// - Returns: The request, or `nil` when `url` does not parse.
    func makeURLRequest(replayOf originalID: String) -> URLRequest? {
        guard let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else { return nil }
        let mutable = NSMutableURLRequest(url: parsed)
        mutable.httpMethod = method
        for header in headers where !Self.managedHeaderNames.contains(header.name.lowercased()) {
            mutable.addValue(header.value, forHTTPHeaderField: header.name)
        }
        mutable.httpBody = body
        URLProtocol.setProperty(originalID, forKey: replayOfRequestKey, in: mutable)
        return mutable as URLRequest
    }

    /// Whether anything differs from the draft this one started as.
    func isModified(from original: ReplayableRequest) -> Bool { self != original }
}
```

- [ ] **Step 6: Write `ReplayComparison`**

```swift
/// The difference between an original request and one of its replays.
struct ReplayComparison: Equatable, Sendable {
    /// Whether the status code differs, treating "no response" as a status of its own.
    let statusChanged: Bool
    /// Replay duration minus original, in milliseconds. Nil while the replay is pending.
    let durationDeltaMilliseconds: Double?
    /// Replay body size minus original, in bytes. Nil while the replay is pending.
    let sizeDeltaBytes: Int?

    /// Compares two captured requests.
    init(original: HTTPRequest, replay: HTTPRequest) {
        statusChanged = original.responseCode != replay.responseCode
        if let originalDuration = original.requestDuration, let replayDuration = replay.requestDuration {
            durationDeltaMilliseconds = Double(replayDuration) - Double(originalDuration)
        } else {
            durationDeltaMilliseconds = nil
        }
        if let originalSize = original.responseBodyLength, let replaySize = replay.responseBodyLength {
            sizeDeltaBytes = replaySize - originalSize
        } else {
            sizeDeltaBytes = nil
        }
    }
}
```

- [ ] **Step 7: Run to verify both pass**

Expected: `** TEST SUCCEEDED **` with 9 new tests.

- [ ] **Step 8: Commit**

```bash
git add Sources/Scyther/Features/RequestReplay Sources/Scyther/Features/NetworkLogger/HTTPInterceptorURLProtocol.swift Tests/ScytherTests/Features/ReplayableRequestTests.swift Tests/ScytherTests/Features/ReplayComparisonTests.swift
git commit -m "Add the replay draft and comparison types"
```

---

### Task 2: Capture-side provenance

**Files:**
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPRequest.swift`
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPInterceptorURLProtocol.swift`
- Modify: `Sources/Scyther/Features/NetworkLogger/HTTPResponseView.swift`
- Test: append `ReplayInterceptorTests` to `Tests/ScytherTests/Features/ReplayableRequestTests.swift`

**Interfaces:**
- Consumes: `replayOfRequestKey`, `ReplayableRequest.makeURLRequest(replayOf:)`.
- Produces: `HTTPRequest.replayOfID: String?`.

- [ ] **Step 1: Write the failing provenance test**

```swift
final class ReplayInterceptorTests: XCTestCase {

    func testACapturedReplayRecordsWhatItReplays() throws {
        let mutable = NSMutableURLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        mutable.httpMethod = "GET"
        URLProtocol.setProperty("original-hash", forKey: replayOfRequestKey, in: mutable)

        let model = HTTPRequest()
        model.saveRequest(mutable as URLRequest)
        XCTAssertEqual(model.replayOfID, "original-hash")
    }

    func testAnOrdinaryRequestRecordsNoProvenance() {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        request.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(request)
        XCTAssertNil(model.replayOfID)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `value of type 'HTTPRequest' has no member 'replayOfID'`.

- [ ] **Step 3: Add the field and read it**

In `HTTPRequest`, with `///` docs:

```swift
    /// The `getRandomHash()` value of the request this one replays, if it is a replay.
    var replayOfID: String?
```

In `HTTPRequest.saveRequest(_:)`, alongside the other assignments:

```swift
        replayOfID = URLProtocol.property(forKey: replayOfRequestKey, in: request) as? String
```

Reading it in `saveRequest` rather than in the protocol keeps the interceptor untouched and makes the behaviour unit-testable without a network, which is why the test above drives `saveRequest` directly.

- [ ] **Step 4: Add the REPLAY badge**

In `HTTPResponseView`, add a `REPLAY` lozenge shown when `viewModel.isReplay` is true, using the same badge treatment as the GraphQL badges (`.font(.system(size: 9, weight: .bold))`, white foreground, 6/1 padding, `RoundedRectangle(cornerRadius: 4)` background). Its colour is `Color.purple`. Add `var isReplay: Bool { request.replayOfID != nil }` to the row's view model.

- [ ] **Step 5: Run to verify it passes**

Expected: `** TEST SUCCEEDED **` with 2 more tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/Scyther/Features/NetworkLogger Tests/ScytherTests/Features/ReplayableRequestTests.swift
git commit -m "Record which request a replay came from"
```

---

### Task 3: The editor, the comparison UI, and documentation

**Files:**
- Create: `Sources/Scyther/Features/RequestReplay/ReplayEditorView.swift`, `ReplayEditorViewModel.swift`
- Modify: `LogDetailsView.swift`, `LogDetailsViewModel.swift`, `NetworkLogsViewModel.swift`
- Modify: `Scripts/localization/strings/NetworkLogger.json`, `README.md`, `Sources/Scyther/Scyther.docc/NetworkDebugging.md`
- Test: `Tests/ScytherTests/Features/ReplayEditorViewModelTests.swift`

**Interfaces:**
- Consumes: `ReplayableRequest`, `ReplayComparison`, `HTTPRequest`.
- Produces: `ReplayEditorViewModel(capturing:session:)` with `draft`, `canSend`, `isModified`, `requiresConfirmation`, `send()`; `NetworkLogsViewModel.replays(of:in:) -> [HTTPRequest]` and `original(of:in:) -> HTTPRequest?`.

- [ ] **Step 1: Write the failing editor tests**

```swift
//
//  ReplayEditorViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class ReplayEditorViewModelTests: XCTestCase {

    private func capture(method: String = "GET") -> HTTPRequest {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        request.httpMethod = method
        let model = HTTPRequest()
        model.saveRequest(request)
        return model
    }

    func testSendIsDisabledForAnInvalidURL() {
        let viewModel = ReplayEditorViewModel(capturing: capture())
        XCTAssertTrue(viewModel.canSend)
        viewModel.draft.url = "not a url"
        XCTAssertFalse(viewModel.canSend)
    }

    func testSendIsDisabledForAnEmptyMethod() {
        let viewModel = ReplayEditorViewModel(capturing: capture())
        viewModel.draft.method = "  "
        XCTAssertFalse(viewModel.canSend)
    }

    func testNonIdempotentMethodsRequireConfirmation() {
        for method in ["POST", "PATCH", "DELETE", "post"] {
            let viewModel = ReplayEditorViewModel(capturing: capture(method: method))
            XCTAssertTrue(viewModel.requiresConfirmation, "\(method) can change server state twice")
        }
        for method in ["GET", "HEAD", "OPTIONS"] {
            let viewModel = ReplayEditorViewModel(capturing: capture(method: method))
            XCTAssertFalse(viewModel.requiresConfirmation)
        }
    }

    func testEditingAHeaderMarksTheDraftModified() {
        let viewModel = ReplayEditorViewModel(capturing: capture())
        XCTAssertFalse(viewModel.isModified)
        viewModel.draft.headers.append(.init(name: "X-Debug", value: "1"))
        XCTAssertTrue(viewModel.isModified)
    }

    func testRemovingAHeaderMarksTheDraftModified() {
        let capture = capture()
        let viewModel = ReplayEditorViewModel(capturing: capture)
        viewModel.draft.headers.append(.init(name: "X-Debug", value: "1"))
        let count = viewModel.draft.headers.count
        viewModel.draft.headers.removeLast()
        XCTAssertEqual(viewModel.draft.headers.count, count - 1)
        XCTAssertFalse(viewModel.isModified, "removing the added header returns the draft to its original state")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'ReplayEditorViewModel' in scope`.

- [ ] **Step 3: Write the view model**

```swift
/// Backs ``ReplayEditorView``: holds the editable draft, validates it, and sends it.
@MainActor
final class ReplayEditorViewModel: ViewModel {
    /// The request being replayed.
    let capture: HTTPRequest
    /// The editable copy shown in the form.
    @Published var draft: ReplayableRequest
    /// Whether the confirmation alert is showing.
    @Published var showingConfirmation: Bool = false

    private let original: ReplayableRequest
    private let session: URLSession

    /// Creates a view model for replaying `capture`.
    ///
    /// - Parameters:
    ///   - capture: The captured request to start from.
    ///   - session: The session the replay is sent through. Injected for tests; the replay is
    ///     captured by the interceptor either way.
    init(capturing capture: HTTPRequest, session: URLSession = .shared) {
        self.capture = capture
        let draft = ReplayableRequest(capturing: capture)
        self.draft = draft
        self.original = draft
        self.session = session
        super.init()
    }

    /// Whether the draft can be sent: a non-empty method and a URL that parses.
    var canSend: Bool {
        !draft.method.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.makeURLRequest(replayOf: capture.getRandomHash() as String) != nil
    }

    /// Whether anything has been edited since the editor opened.
    var isModified: Bool { draft.isModified(from: original) }

    /// Whether sending could change server state twice and should ask first.
    var requiresConfirmation: Bool {
        !["GET", "HEAD", "OPTIONS"].contains(draft.method.uppercased())
    }

    /// Sends the draft. The response is captured by the interceptor like any app request.
    func send() {
        guard let request = draft.makeURLRequest(replayOf: capture.getRandomHash() as String) else { return }
        session.dataTask(with: request).resume()
    }
}
```

- [ ] **Step 4: Write the editor view**

`ReplayEditorView`, a sheet in a `NavigationStack`:

- **Method** — a `Picker` of `GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS` plus an "Other" case revealing a `TextField`.
- **URL** — a `TextField` with `.autocorrectionDisabled()` and `.textInputAutocapitalization(.never)`; a red caption appears when the URL will not parse.
- **Headers** — a `ForEach` over `draft.headers` with editable name and value fields and `.onDelete`; an add row appends an empty header. A header whose lowercased name is in `ReplayableRequest.managedHeaderNames` renders `.disabled(true)` with a `localized("Managed by the system")` caption.
- **Body** — a `NavigationLink` to `TextEntryView` showing a byte count. A body that is not valid UTF-8 shows `localized("Binary body, sent unchanged")` and is not editable.
- **Send** — a toolbar confirmation-role button, disabled unless `canSend`. When `requiresConfirmation`, it sets `showingConfirmation`; the `.alert` names the method and offers a destructive **Send** and a cancel. Otherwise it calls `send()` and dismisses.

- [ ] **Step 5: Wire the detail page**

In `LogDetailsView`, add a **Replay request** button in the Developer section, hidden when `viewModel.wasStubbed` is true (that field exists only if the Network Rules plan has been merged; guard with `#if` is not needed since the property will exist or the plan is not merged — if it is absent, omit the condition).

Add to `NetworkLogsViewModel`, as pure statics so they are testable:

```swift
    /// Every replay of `request` present in `items`.
    nonisolated static func replays(of request: HTTPRequest, in items: [HTTPRequest]) -> [HTTPRequest] {
        let hash = request.getRandomHash() as String
        return items.filter { $0.replayOfID == hash }
    }

    /// The request `replay` was built from, if it is still in the log.
    nonisolated static func original(of replay: HTTPRequest, in items: [HTTPRequest]) -> HTTPRequest? {
        guard let id = replay.replayOfID else { return nil }
        return items.first { ($0.getRandomHash() as String) == id }
    }
```

`LogDetailsView` gains a **Replays** section listing each replay with its status and, via `ReplayComparison`, its duration and size deltas, each linking to that replay's detail page; and, on a replay, an **Original** row linking back.

- [ ] **Step 6: Localise**

Every new literal through `localized(_:)`, keys added to `Scripts/localization/strings/NetworkLogger.json` in all twelve languages, then `python3 Scripts/localization/build_catalog.py`.

- [ ] **Step 7: Run everything and verify manually**

Full test command, then the example app build. Install, launch, make a sample request, open its detail page, tap **Replay request**, add a header, send, and confirm a new row appears with the REPLAY badge and the original's detail page lists it under Replays with a duration delta.

- [ ] **Step 8: Documentation**

README gains a **Request Replay** subsection under Networking covering the editor, the badge, the comparison, and the non-idempotent confirmation. `NetworkDebugging.md` mirrors it.

- [ ] **Step 9: Commit**

```bash
git add Sources/Scyther/Features/RequestReplay Sources/Scyther/Features/NetworkLogger Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings README.md Sources/Scyther/Scyther.docc
git commit -m "Add the request replay editor and comparison"
```

---

## Self-review

- **Spec coverage:** Component 1 → Task 1 (`ReplayableRequest`, ordered headers, provenance stamping, managed headers). Component 2 → Task 2 (`replayOfID`, REPLAY badge). Component 3 → Task 3 (the editor and every field it names). Component 4 → Task 3 (`ReplayComparison`, Replays section, Original row). Component 5 → the test files in all three tasks.
- **Placeholders:** none.
- **Type consistency:** `ReplayableRequest(capturing:)`, `makeURLRequest(replayOf:)`, `isModified(from:)`, `managedHeaderNames`, `ReplayComparison(original:replay:)`, `replayOfRequestKey`, `ReplayEditorViewModel(capturing:session:)` are spelled identically in every task.
- **One deviation from the spec, deliberate:** the spec puts the provenance read in `HTTPInterceptorURLProtocol.startLoading()`. The plan reads it in `HTTPRequest.saveRequest(_:)` instead — the same three lines, but reachable from a unit test without a network, which is why Task 2's tests can exist at all. The interceptor calls `saveRequest` as its first act, so the behaviour is identical.
