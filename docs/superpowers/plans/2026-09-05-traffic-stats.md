# Traffic Stats and Waterfall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A screen reached from Network Logs that answers what is slow, what is failing, and what overlaps, computed entirely from requests already in memory.

**Architecture:** Two pure value types do all the work — `TrafficStatistics.compute(from:)` for the figures and `WaterfallSeries.build(from:limit:)` for the timeline — so every number is unit-testable with no network and no view. The screen observes the same filtered array the log shows, so the active search and filter chips narrow the stats. Charts use Swift Charts, which is in the iOS 16 SDK and adds no dependency.

**Tech Stack:** Swift 6 (language mode v6, strict concurrency), SwiftUI, Swift Charts, XCTest, iOS 16+, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-05-traffic-stats-design.md`

**Prerequisite:** none. Independent of the other three networking plans.

## Global Constraints

- **iOS only.** Never build for macOS. `swift build` does not work.
- **Build and test on the booted simulator.** `S=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for v in d.values() for x in v if x["state"]=="Booted"))')`; if none, `xcrun simctl boot 0EEED0FF-A025-468E-9466-3BDE708B41B0`.
- **Full test command:** `xcodebuild test -scheme Scyther -destination "platform=iOS Simulator,id=$S" -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|failed \(|Executed [0-9]+ tests|TEST " | sort -u | tail -8`
- **Every figure is computed in a pure type.** No statistics arithmetic in a view or a view model beyond formatting.
- **Percentiles use the nearest-rank method** on completed requests only. A pending request is counted separately, never as a zero-duration completion.
- **Below five completed requests the summary shows raw durations, not percentiles** — a median of three samples is noise.
- **Swift 6 strict concurrency.** `TrafficStatistics` and `WaterfallSeries` are `Sendable` value types; computation runs on a detached task the way `NetworkLogsViewModel` already filters.
- **Minimum deployment target iOS 16.** Swift Charts is available; `import Charts` needs no availability guard on this floor. **MVVM**, view models in their own files. **DocC `///` on every new type and member.**
- **Chart text takes its colour from the theme**, never a literal, so it reads in light and dark.
- **Every user-facing string through `localized(_:)`**, keys added to `Scripts/localization/strings/TrafficStats.json` in all twelve languages (`fr, de, es, it, pt-BR, nl, ja, zh-Hans, zh-Hant, ko, ru, ar`), then `python3 Scripts/localization/build_catalog.py`. `grep -l '"<key>"' Scripts/localization/strings/*.json` before adding any key. Counted strings get `plural` variations with the CLDR categories for each language (ru: one/few/many/other; ar: zero/one/two/few/many/other; ja/zh/ko: other only).
- **Never put a Claude session URL or any Claude mention in a commit message, PR body, or documentation.**
- **Exact names:** module `Sources/Scyther/Features/TrafficStats/`. There is **no menu row**: the screen is reached from a toolbar button on Network Logs, because it describes the filtered list you are looking at.

---

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `Sources/Scyther/Features/TrafficStats/TrafficStatistics.swift` | Summary, host and endpoint breakdowns |
| `Sources/Scyther/Features/TrafficStats/WaterfallSeries.swift` | Timeline entries on a shared axis |
| `Sources/Scyther/Features/TrafficStats/TrafficStatsView.swift` | The screen |
| `Sources/Scyther/Features/TrafficStats/TrafficStatsViewModel.swift` | Debounced recomputation |
| `Scripts/localization/strings/TrafficStats.json` | Strings |
| `Tests/ScytherTests/Features/TrafficStatisticsTests.swift` | Percentiles, failures, grouping |
| `Tests/ScytherTests/Features/WaterfallSeriesTests.swift` | Origin, offsets, limit, pending |
| `Tests/ScytherTests/Features/TrafficStatsViewModelTests.swift` | Recomputation and the caption |

**Modified:** `NetworkLogsView.swift` (toolbar button), `README.md`, `Sources/Scyther/Scyther.docc/NetworkDebugging.md`.

---

### Task 1: `TrafficStatistics`

**Files:**
- Create: `Sources/Scyther/Features/TrafficStats/TrafficStatistics.swift`
- Test: `Tests/ScytherTests/Features/TrafficStatisticsTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest` (`requestDate`, `requestDuration`, `responseCode`, `responseBodyLength`, `requestMethod`, `host`).
- Produces: `TrafficStatistics` with `Summary`, `HostBreakdown`, `EndpointBreakdown`, `static func compute(from: [HTTPRequest]) -> TrafficStatistics`, `static func endpointIdentity(for: HTTPRequest) -> String`, and `static let empty: TrafficStatistics` (a zeroed summary with no breakdowns, used as the view model's initial value).

- [ ] **Step 1: Write the failing tests**

```swift
//
//  TrafficStatisticsTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class TrafficStatisticsTests: XCTestCase {

    private func request(
        url: String = "https://api.example.com/v1/users",
        method: String = "GET",
        status: Int? = 200,
        duration: Float? = 100,
        size: Int? = 500
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = method
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.responseCode = status
        model.requestDuration = duration
        model.responseBodyLength = size
        model.noResponse = status == nil
        return model
    }

    // MARK: Percentiles

    func testMedianOfAnOddCount() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 10), request(duration: 30), request(duration: 20),
            request(duration: 40), request(duration: 50),
        ])
        XCTAssertEqual(stats.summary.medianDuration, 30)
    }

    func testMedianOfAnEvenCountUsesNearestRank() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 10), request(duration: 20), request(duration: 30),
            request(duration: 40), request(duration: 50), request(duration: 60),
        ])
        XCTAssertEqual(stats.summary.medianDuration, 30, "nearest rank takes the lower of the two middles")
    }

    func testP95OfTwentyRequests() {
        let stats = TrafficStatistics.compute(from: (1...20).map { request(duration: Float($0 * 10)) })
        XCTAssertEqual(stats.summary.p95Duration, 190)
    }

    func testNoCompletedRequestsHasNoPercentiles() {
        let stats = TrafficStatistics.compute(from: [request(status: nil, duration: nil, size: nil)])
        XCTAssertNil(stats.summary.medianDuration)
        XCTAssertNil(stats.summary.p95Duration)
        XCTAssertEqual(stats.summary.pendingCount, 1)
    }

    func testPendingRequestsAreExcludedFromPercentiles() {
        let stats = TrafficStatistics.compute(from: [
            request(duration: 100), request(duration: 200),
            request(status: nil, duration: nil, size: nil),
        ])
        XCTAssertEqual(stats.summary.medianDuration, 100)
        XCTAssertEqual(stats.summary.requestCount, 3)
        XCTAssertEqual(stats.summary.pendingCount, 1)
    }

    // MARK: Failures

    func testFailuresCountClientServerErrorsAndNoResponse() {
        let stats = TrafficStatistics.compute(from: [
            request(status: 200), request(status: 404), request(status: 500),
            request(status: nil, duration: nil, size: nil), request(status: 301),
        ])
        XCTAssertEqual(stats.summary.failureCount, 3, "404, 500 and the pending entry")
    }

    // MARK: Bytes

    func testBytesReceivedSumsResponseSizes() {
        let stats = TrafficStatistics.compute(from: [request(size: 100), request(size: 250), request(size: nil)])
        XCTAssertEqual(stats.summary.bytesReceived, 350)
    }

    // MARK: Endpoint identity

    func testEndpointIdentityStripsTheQuery() {
        let identity = TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/v1/users?page=2"))
        XCTAssertEqual(identity, "GET api.example.com/v1/users")
    }

    func testEndpointIdentityCollapsesNumericSegments() {
        XCTAssertEqual(
            TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/v1/users/42/posts/7")),
            "GET api.example.com/v1/users/:id/posts/:id"
        )
    }

    func testEndpointIdentityCollapsesUUIDSegments() {
        let uuid = "8B1E2C5A-3F4D-4E5A-9C6B-7D8E9F0A1B2C"
        XCTAssertEqual(
            TrafficStatistics.endpointIdentity(for: request(url: "https://api.example.com/v1/orders/\(uuid)")),
            "GET api.example.com/v1/orders/:id"
        )
    }

    func testEndpointsAggregateAcrossIdentifiers() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://api.example.com/v1/users/1", duration: 100),
            request(url: "https://api.example.com/v1/users/2", duration: 300),
        ])
        XCTAssertEqual(stats.endpoints.count, 1)
        XCTAssertEqual(stats.endpoints.first?.requestCount, 2)
        XCTAssertEqual(stats.endpoints.first?.slowestDuration, 300)
    }

    // MARK: Ordering

    func testEndpointsAreSortedBySlowestFirst() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://api.example.com/fast", duration: 10),
            request(url: "https://api.example.com/slow", duration: 900),
        ])
        XCTAssertEqual(stats.endpoints.map(\.slowestDuration), [900, 10])
    }

    func testHostsAreSortedByFailuresThenMedianDuration() {
        let stats = TrafficStatistics.compute(from: [
            request(url: "https://clean.example.com/a", status: 200, duration: 500),
            request(url: "https://broken.example.com/a", status: 500, duration: 10),
        ])
        XCTAssertEqual(stats.hosts.map(\.id), ["broken.example.com", "clean.example.com"])
    }

    func testAnEmptyInputProducesAnEmptySummary() {
        let stats = TrafficStatistics.compute(from: [])
        XCTAssertEqual(stats.summary.requestCount, 0)
        XCTAssertTrue(stats.hosts.isEmpty)
        XCTAssertTrue(stats.endpoints.isEmpty)
        XCTAssertNil(stats.summary.medianDuration)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run the full test command. Expected: `cannot find 'TrafficStatistics' in scope`.

- [ ] **Step 3: Write the type**

The stored properties are exactly as the spec's Component 1 lists them, each with `///` docs. The parts worth writing out:

```swift
    /// The nearest-rank value at `percentile` (0...1) of a sorted sample.
    ///
    /// Nearest rank rather than interpolation, so every reported figure is a duration that a
    /// request actually took rather than a number between two of them.
    private static func percentile(_ percentile: Double, of sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = max(1, Int((percentile * Double(sorted.count)).rounded(.up)))
        return sorted[min(rank, sorted.count) - 1]
    }

    /// A stable identity for grouping requests by endpoint.
    ///
    /// The query string is dropped and any path segment that is purely numeric, or a UUID, is
    /// replaced with `:id`. Without that collapse a REST API produces one endpoint per record and
    /// the breakdown is useless.
    static func endpointIdentity(for request: HTTPRequest) -> String {
        let method = (request.requestMethod ?? "GET").uppercased()
        guard let url = request.requestURL,
              let components = URLComponents(string: url),
              let host = components.host else {
            return method
        }
        let segments = components.path.split(separator: "/").map { segment -> String in
            let text = String(segment)
            if !text.isEmpty, text.allSatisfy(\.isNumber) { return ":id" }
            if UUID(uuidString: text) != nil { return ":id" }
            return text
        }
        let path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return "\(method) \(host)\(path)"
    }
```

`compute(from:)` walks the array once, collecting completed durations, failure counts (`responseCode ?? 0 >= 400` or `noResponse`), byte totals, and per-host and per-endpoint buckets keyed by `host` and `endpointIdentity(for:)`, then sorts hosts by `failureCount` descending then `medianDuration` descending, and endpoints by `slowestDuration` descending.

- [ ] **Step 4: Run to verify it passes**

Expected: `** TEST SUCCEEDED **` with 14 new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/TrafficStatistics.swift Tests/ScytherTests/Features/TrafficStatisticsTests.swift
git commit -m "Add traffic statistics"
```

---

### Task 2: `WaterfallSeries`

**Files:**
- Create: `Sources/Scyther/Features/TrafficStats/WaterfallSeries.swift`
- Test: `Tests/ScytherTests/Features/WaterfallSeriesTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest` (`requestDate`, `requestDuration`, `responseCode`, `noResponse`, `isGraphQL`, `graphQLOperationName`, `requestMethod`, `requestURL`, `getRandomHash()`).
- Produces: `WaterfallEntry` (`id`, `label`, `start`, `duration`, `isFailure`, `isPending`); `WaterfallSeries` (`origin`, `span`, `entries`, `static func build(from:limit:) -> WaterfallSeries`, `static let empty: WaterfallSeries` with no entries and a zero span).

- [ ] **Step 1: Write the failing tests**

```swift
//
//  WaterfallSeriesTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class WaterfallSeriesTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func request(
        offset: TimeInterval,
        duration: Float? = 100,
        status: Int? = 200,
        url: String = "https://api.example.com/v1/users",
        graphQL: String? = nil
    ) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.requestDate = base.addingTimeInterval(offset)
        model.requestDuration = duration
        model.responseCode = status
        model.noResponse = status == nil
        if let graphQL {
            model.isGraphQL = true
            model.graphQLOperationName = graphQL
        }
        return model
    }

    func testOriginIsTheEarliestStart() {
        let series = WaterfallSeries.build(from: [request(offset: 5), request(offset: 0), request(offset: 2)])
        XCTAssertEqual(series.origin, base)
        XCTAssertEqual(series.entries.map(\.start).min(), 0)
    }

    func testOffsetsAreSecondsFromTheOrigin() {
        let series = WaterfallSeries.build(from: [request(offset: 0), request(offset: 3)])
        XCTAssertEqual(series.entries.map(\.start).sorted(), [0, 3])
    }

    func testDurationIsConvertedFromMillisecondsToSeconds() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: 250)])
        XCTAssertEqual(series.entries.first?.duration ?? 0, 0.25, accuracy: 0.0001)
    }

    func testSpanCoversTheLastRequestsEnd() {
        let series = WaterfallSeries.build(from: [request(offset: 0, duration: 500), request(offset: 2, duration: 1_000)])
        XCTAssertEqual(series.span, 3, accuracy: 0.0001)
    }

    func testAPendingRequestRunsToTheEndOfTheSpan() {
        let series = WaterfallSeries.build(from: [
            request(offset: 0, duration: 2_000),
            request(offset: 1, duration: nil, status: nil),
        ])
        let pending = series.entries.first { $0.isPending }
        XCTAssertEqual(pending?.start ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual((pending?.start ?? 0) + (pending?.duration ?? 0), series.span, accuracy: 0.0001)
    }

    func testTheLimitKeepsTheMostRecentEntries() {
        let requests = (0..<10).map { request(offset: TimeInterval($0)) }
        let series = WaterfallSeries.build(from: requests, limit: 3)
        XCTAssertEqual(series.entries.count, 3)
        XCTAssertEqual(series.origin, base.addingTimeInterval(7))
    }

    func testLabelPrefersTheGraphQLOperationName() {
        let series = WaterfallSeries.build(from: [request(offset: 0, graphQL: "GetUser")])
        XCTAssertEqual(series.entries.first?.label, "GetUser")
    }

    func testLabelFallsBackToMethodAndPath() {
        let series = WaterfallSeries.build(from: [request(offset: 0, url: "https://api.example.com/v1/users?page=2")])
        XCTAssertEqual(series.entries.first?.label, "GET /v1/users")
    }

    func testFailuresAreFlagged() {
        let series = WaterfallSeries.build(from: [request(offset: 0, status: 500)])
        XCTAssertTrue(series.entries.first?.isFailure ?? false)
    }

    func testAnEmptyInputProducesAnEmptySeries() {
        let series = WaterfallSeries.build(from: [])
        XCTAssertTrue(series.entries.isEmpty)
        XCTAssertEqual(series.span, 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'WaterfallSeries' in scope`.

- [ ] **Step 3: Write the type**

`build(from:limit:)` sorts by `requestDate`, takes the last `limit`, sets `origin` to the earliest `requestDate` (or `Date()` when empty), computes each entry's `start` as `requestDate.timeIntervalSince(origin)` and `duration` as `Double(requestDuration ?? 0) / 1000`, sets `span` to the greatest `start + duration` (minimum 0), then makes a second pass so any pending entry's `duration` runs to `span - start`. `isFailure` is `responseCode ?? 0 >= 400 || noResponse`; `isPending` is `noResponse`.

- [ ] **Step 4: Run to verify it passes**

Expected: `** TEST SUCCEEDED **` with 10 more tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/WaterfallSeries.swift Tests/ScytherTests/Features/WaterfallSeriesTests.swift
git commit -m "Add the traffic waterfall series"
```

---

### Task 3: The screen and documentation

**Files:**
- Create: `Sources/Scyther/Features/TrafficStats/TrafficStatsView.swift`, `TrafficStatsViewModel.swift`
- Create: `Scripts/localization/strings/TrafficStats.json`
- Modify: `Sources/Scyther/Features/NetworkLogger/NetworkLogsView.swift`, `README.md`, `Sources/Scyther/Scyther.docc/NetworkDebugging.md`
- Test: `Tests/ScytherTests/Features/TrafficStatsViewModelTests.swift`

**Interfaces:**
- Consumes: `TrafficStatistics`, `WaterfallSeries`, the filtered `[HTTPRequest]` from `NetworkLogsViewModel`.
- Produces: `TrafficStatsViewModel(requests:totalCount:)` with `statistics`, `waterfall`, `captionCount`, `isFiltered`, `recompute()`.

- [ ] **Step 1: Write the failing view model tests**

```swift
//
//  TrafficStatsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class TrafficStatsViewModelTests: XCTestCase {

    private func request(duration: Float) -> HTTPRequest {
        var urlRequest = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        urlRequest.httpMethod = "GET"
        let model = HTTPRequest()
        model.saveRequest(urlRequest)
        model.requestDate = Date()
        model.requestDuration = duration
        model.responseCode = 200
        model.responseBodyLength = 10
        return model
    }

    func testStatisticsAreComputedOnInit() async {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.statistics.summary.requestCount, 1)
        XCTAssertEqual(viewModel.waterfall.entries.count, 1)
    }

    func testUpdatingTheRequestsRecomputes() async {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        await viewModel.recompute()
        viewModel.update(requests: [request(duration: 100), request(duration: 200)], totalCount: 2)
        await viewModel.recompute()
        XCTAssertEqual(viewModel.statistics.summary.requestCount, 2)
    }

    func testTheCaptionReportsFilteredAndTotalCounts() {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 340)
        XCTAssertTrue(viewModel.isFiltered)
        XCTAssertEqual(viewModel.captionCount, 1)
        XCTAssertEqual(viewModel.totalCount, 340)
    }

    func testAnUnfilteredListIsNotReportedAsFiltered() {
        let viewModel = TrafficStatsViewModel(requests: [request(duration: 100)], totalCount: 1)
        XCTAssertFalse(viewModel.isFiltered)
    }

    func testFewCompletedRequestsSuppressesPercentiles() async {
        let viewModel = TrafficStatsViewModel(
            requests: (0..<4).map { request(duration: Float(($0 + 1) * 10)) },
            totalCount: 4
        )
        await viewModel.recompute()
        XCTAssertFalse(
            viewModel.showsPercentiles,
            "a median of four samples is noise; the summary shows raw durations instead"
        )
    }

    func testFiveOrMoreCompletedRequestsShowsPercentiles() async {
        let viewModel = TrafficStatsViewModel(
            requests: (0..<5).map { request(duration: Float(($0 + 1) * 10)) },
            totalCount: 5
        )
        await viewModel.recompute()
        XCTAssertTrue(viewModel.showsPercentiles)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: `cannot find 'TrafficStatsViewModel' in scope`.

- [ ] **Step 3: Write the view model**

`TrafficStatsViewModel: ViewModel` holds `@Published private(set) var statistics: TrafficStatistics = .empty` and `@Published private(set) var waterfall: WaterfallSeries = .empty`, plus `requests`, `totalCount`, `captionCount` (`requests.count`), `isFiltered` (`requests.count != totalCount`), and `showsPercentiles` (`statistics.summary.requestCount - statistics.summary.pendingCount >= 5`). `update(requests:totalCount:)` stores the new input; `recompute()` runs both `compute` calls on a detached task, exactly as `NetworkLogsViewModel.updateData()` does its filtering, and assigns on the main actor. The view calls `recompute()` from `.onFirstAppear` and from an `.onChange` debounced at 500 ms with the same `PassthroughSubject` pattern the log's search already uses.

- [ ] **Step 4: Write the screen**

`TrafficStatsView`, a `List`:

1. **Caption** — `localized("%lld of %lld requests")` when filtered, `localized("%lld requests")` otherwise, both plural keys.
2. **Summary** — `LabeledContent` rows for requests, failures, median and p95 (or the raw durations when `showsPercentiles` is false), and bytes received. `.monospacedDigit()` on the values. The failure row takes `Color.red` only when the count is non-zero.
3. **Waterfall** — a `Chart` over `waterfall.entries` with a `BarMark(xStart:xEnd:y:)` per entry, `.foregroundStyle` by outcome, `chartXAxisLabel(localized("Seconds"))`, and axis text using `Color.primary` and `Color.secondary` rather than literals. The chart's height is `max(120, CGFloat(entries.count) * 18)` inside a `ScrollView` so 40 bars stay legible.
4. **Slowest endpoints** — a row per `EndpointBreakdown` with its identity, count, median and slowest.
5. **By host** — a row per `HostBreakdown` with count, failures and median.

An empty state replaces the whole list when there are no requests, explaining that stats appear once traffic is captured.

- [ ] **Step 5: Add the toolbar entry point**

In `NetworkLogsView`, add a toolbar button beside the existing export and delete buttons:

```swift
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrafficStatsView(
                        viewModel: TrafficStatsViewModel(
                            requests: viewModel.requests,
                            totalCount: viewModel.totalRequestCount
                        )
                    )
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .accessibilityLabel(localized("Traffic Stats"))
                .disabled(viewModel.requests.isEmpty)
            }
```

Add `var totalRequestCount: Int { items.count }` to `NetworkLogsViewModel`, exposing the unfiltered count the caption needs.

- [ ] **Step 6: Localise**

Every literal through `localized(_:)`, keys in `Scripts/localization/strings/TrafficStats.json` in all twelve languages with plural variations for the two counted strings, then `python3 Scripts/localization/build_catalog.py`.

- [ ] **Step 7: Run everything and verify manually**

Full test command, then the example app build. Install, launch, tap **Make Multiple Requests** several times, open Network Logs, tap the chart button, and confirm: the waterfall shows overlapping bars, the endpoint list aggregates `/todos/1` style paths, and applying a filter chip changes both the caption and the figures. Take one screenshot in dark mode to confirm the chart's labels are legible.

- [ ] **Step 8: Documentation**

README gains a **Traffic Stats** subsection under Networking: what the figures mean, that they follow the active filter, the nearest-rank percentile choice, and the five-request threshold. `NetworkDebugging.md` mirrors it.

- [ ] **Step 9: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats Sources/Scyther/Features/NetworkLogger/NetworkLogsView.swift Sources/Scyther/Features/NetworkLogger/NetworkLogsViewModel.swift Scripts/localization Sources/Scyther/Resources/Localizable.xcstrings README.md Sources/Scyther/Scyther.docc
git commit -m "Add the traffic stats screen"
```

---

## Self-review

- **Spec coverage:** Component 1 → Task 1. Component 2 → Task 2. Component 3 → Task 3 (toolbar entry point, the four sections, the caption, the empty state). Component 4 → the test file in each task.
- **Placeholders:** none.
- **Type consistency:** `TrafficStatistics.compute(from:)`, `endpointIdentity(for:)`, `WaterfallSeries.build(from:limit:)`, `TrafficStatsViewModel(requests:totalCount:)`, `update(requests:totalCount:)`, `recompute()`, `showsPercentiles` are spelled identically in every task. `TrafficStatistics.empty` and `WaterfallSeries.empty` are referenced by Task 3 and must be declared in Tasks 1 and 2 respectively — added to those tasks' Interfaces.
- **One spec requirement the plan sharpens:** the spec says endpoint identity collapses "a numeric path segment". The plan also collapses UUID segments, because a REST API keyed on UUIDs is at least as common and would otherwise defeat the aggregation entirely. Task 1 tests both.
