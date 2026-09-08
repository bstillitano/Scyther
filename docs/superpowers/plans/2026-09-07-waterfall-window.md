# Waterfall Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the full-page waterfall's zoomed absolute axis with a compressed full-span strip that drives a detail list containing only the requests the current time window holds.

**Architecture:** A new pure value type, `WaterfallWindow`, owns every rule about what slice of time is visible — clamping, zooming, moving. A new `Canvas`-backed `WaterfallOverviewStrip` draws the whole log in one pass and is used twice: on the page with a draggable window overlay, and in Traffic Stats as a tappable summary. `WaterfallView` becomes strip-plus-list, and the two-axis scrolling machinery from 4.5.0 is removed.

**Tech Stack:** Swift 6 language mode, complete strict concurrency, SwiftUI, XCTest, SPM (iOS-only).

**Spec:** `docs/superpowers/specs/2026-09-07-waterfall-window-design.md`

## Global Constraints

- iOS 16 deployment floor. Use `MagnificationGesture`, **not** `MagnifyGesture` (iOS 17).
- Swift 6 complete strict concurrency. `@MainActor` on anything touching UIKit or SwiftUI state; value types crossing actors conform to `Sendable`.
- Build and test for the booted iOS simulator only. `swift build` does not work — this is an iOS-only library requiring UIKit.
  Test command: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- MVVM + Repository. Separate view model files. One responsibility per file.
- **Use the stock SwiftUI component wherever one serves the need** (`List`, `NavigationLink`, `Canvas`, `LabeledContent`, `ContentUnavailableView`). Never hand-roll a row or control SwiftUI already provides.
- Every user-facing string goes through `localized(_:)`, with the key added to `Scripts/localization/strings/TrafficStats.json` in all twelve languages (fr, de, es, it, pt-BR, nl, ja, zh-Hans, zh-Hant, ko, ru, ar), then `python3 Scripts/localization/build_catalog.py` run and the regenerated catalogue committed.
- DocC documentation on every member, including private ones, explaining *why* — not restating the signature.
- Update the README to reflect user-visible changes.
- **No `Claude-Session:` line, Claude mention, or co-author trailer in any commit message.** Check `git log -1 --format=%B` before reporting a task done.
- Colour means status and only status. Do not introduce a per-host colour scale.

---

### Task 1: Put the host on the entry

**Files:**
- Modify: `Sources/Scyther/Features/TrafficStats/WaterfallSeries.swift`
- Test: `Tests/ScytherTests/Features/WaterfallSeriesTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `WaterfallEntry.host: String`, `WaterfallEntry.shortHost: String`, and `WaterfallSeries.shortHost(for host: String) -> String` (internal, static).

Both new fields get a default of `""` in the memberwise initialiser so the three existing `WaterfallEntry(...)` construction sites keep compiling. An entry with no host is a real case — a URL that does not parse — not a placeholder.

- [ ] **Step 1: Write the failing test**

Add to `WaterfallSeriesTests.swift`:

```swift
// MARK: - Short host

func testAGenericFirstLabelIsSkippedInFavourOfTheNameUnderIt() {
    XCTAssertEqual(WaterfallSeries.shortHost(for: "api.ipify.org"), "ipify")
    XCTAssertEqual(WaterfallSeries.shortHost(for: "cdn.assets.example.com"), "assets")
}

func testATwoLabelHostUsesItsFirstLabel() {
    XCTAssertEqual(WaterfallSeries.shortHost(for: "httpbin.org"), "httpbin")
}

func testANonGenericFirstLabelIsKeptEvenWhenTheHostIsLong() {
    XCTAssertEqual(WaterfallSeries.shortHost(for: "jsonplaceholder.typicode.com"), "jsonplaceholder")
    XCTAssertEqual(WaterfallSeries.shortHost(for: "graphqlzero.almansi.me"), "graphqlzero")
}

func testALeadingWWWIsDroppedBeforeAnythingElseIsDecided() {
    XCTAssertEqual(WaterfallSeries.shortHost(for: "www.example.com"), "example")
}

/// An IP address has no label worth picking — "192" names nothing.
func testAnIPAddressIsUsedWhole() {
    XCTAssertEqual(WaterfallSeries.shortHost(for: "192.168.1.1"), "192.168.1.1")
}

func testASingleLabelHostIsUsedWhole() {
    XCTAssertEqual(WaterfallSeries.shortHost(for: "localhost"), "localhost")
}

func testAnEmptyHostStaysEmptyRatherThanInventingOne() {
    XCTAssertEqual(WaterfallSeries.shortHost(for: ""), "")
}

func testAnEntryCarriesTheHostItWasBuiltFrom() {
    let request = HTTPRequest()
    request.requestURL = "https://api.ipify.org/?format=json"
    request.requestMethod = "GET"
    request.requestDate = Date(timeIntervalSince1970: 0)
    request.responseDate = Date(timeIntervalSince1970: 0.2)

    let series = WaterfallSeries.build(from: [request], limit: 10,
                                       now: Date(timeIntervalSince1970: 1))

    XCTAssertEqual(series.entries.first?.host, "api.ipify.org")
    XCTAssertEqual(series.entries.first?.shortHost, "ipify")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/WaterfallSeriesTests`

Expected: FAIL. The first seven fail to **compile** — `shortHost` does not exist — which is a weaker signal than an assertion failure; say so in your report. The eighth fails on an assertion once the others compile.

- [ ] **Step 3: Add the fields to `WaterfallEntry`**

In `WaterfallSeries.swift`, inside `struct WaterfallEntry`, after `label`:

```swift
    /// The request's host, exactly as the URL gave it, or `""` when the URL did not parse.
    ///
    /// Carried so the log detail page and any future grouping have the real thing to work from.
    /// The row draws ``shortHost`` instead, because a row is 402pt wide and
    /// `jsonplaceholder.typicode.com` is not.
    let host: String

    /// The host reduced to the one label worth reading on a row. See
    /// ``WaterfallSeries/shortHost(for:)``.
    let shortHost: String
```

The memberwise initialiser cannot give these defaults — a `let` with an initial value is not
settable through it — so write an explicit initialiser instead, keeping the two new parameters
last so the three existing positional call sites are untouched:

```swift
    /// Creates an entry.
    ///
    /// `host` and `shortHost` default to empty so the chart-style and time-scale tests, which
    /// care about geometry and not about naming, can keep building entries positionally.
    init(id: String,
         label: String,
         start: TimeInterval,
         duration: TimeInterval,
         isFailure: Bool,
         isPending: Bool,
         isStubbed: Bool,
         host: String = "",
         shortHost: String = "") {
        self.id = id
        self.label = label
        self.start = start
        self.duration = duration
        self.isFailure = isFailure
        self.isPending = isPending
        self.isStubbed = isStubbed
        self.host = host
        self.shortHost = shortHost
    }
```

- [ ] **Step 4: Implement `shortHost(for:)`**

Add to `WaterfallSeries`, beside `label(for:)`:

```swift
    /// Host labels that name infrastructure rather than a service, so the label after them is
    /// the one a developer recognises.
    ///
    /// Deliberately short. Every entry here is a label that appears in front of the real name in
    /// ordinary deployments; a longer list starts eating names that mean something.
    private static let genericHostLabels: Set<String> = [
        "api", "www", "cdn", "static", "assets", "app", "m"
    ]

    /// The one label of `host` worth putting on a 402pt-wide row.
    ///
    /// A row has room for roughly fifteen characters of host before the path it is there to show
    /// starts truncating, and `jsonplaceholder.typicode.com` is twenty-eight. The rule picks the
    /// label a developer would say out loud: the first, unless the first names infrastructure
    /// (`api.`, `cdn.`) and there is a real name behind it.
    ///
    /// - Parameter host: A URL's host, or `""`.
    /// - Returns: The display label, lowercased. `""` for an empty host.
    static func shortHost(for host: String) -> String {
        var trimmed = host.lowercased()
        if trimmed.hasPrefix("www.") { trimmed.removeFirst(4) }
        guard !trimmed.isEmpty else { return "" }

        let labels = trimmed.split(separator: ".").map(String.init)
        guard labels.count > 1 else { return trimmed }

        // An IPv4 address has no label worth picking — "192" names nothing.
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return trimmed }

        if labels.count >= 3, genericHostLabels.contains(labels[0]) { return labels[1] }
        return labels[0]
    }
```

- [ ] **Step 5: Populate the fields in `build(from:limit:now:)`**

In the `dated.map { pair -> WaterfallEntry in` closure, before `return WaterfallEntry(`:

```swift
            let host = request.requestURL.flatMap { URLComponents(string: $0)?.host } ?? ""
```

and add to the `WaterfallEntry(...)` call, after `isStubbed:`:

```swift
                host: host,
                shortHost: shortHost(for: host)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/WaterfallSeriesTests`

Expected: PASS, all of them, and the two pre-existing entry-construction sites in `WaterfallChartStyleTests` and `WaterfallTimeScaleTests` still compile.

- [ ] **Step 7: Run the full suite**

Run the full test command from Global Constraints. Expected: no failures.

- [ ] **Step 8: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/WaterfallSeries.swift \
        Tests/ScytherTests/Features/WaterfallSeriesTests.swift
git commit -m "Carry the host on each waterfall entry

A row labelled GET /json is unreadable once two hosts serve a /json, and the
entry had no host to draw. It carries both the real host and the one label
worth putting on a 402pt row."
```

---

### Task 2: The window value type

**Files:**
- Create: `Sources/Scyther/Features/TrafficStats/WaterfallWindow.swift`
- Test: `Tests/ScytherTests/Features/WaterfallWindowTests.swift`

**Interfaces:**
- Consumes: `WaterfallEntry` from Task 1 (only `start` and `duration`).
- Produces:
  - `struct WaterfallWindow: Equatable, Sendable`
  - `init(span: TimeInterval, narrowest: TimeInterval)` — the widest window
  - `init(start: TimeInterval, duration: TimeInterval, span: TimeInterval, narrowest: TimeInterval)` — clamping
  - `static func narrowestDuration(shortestMeasured: TimeInterval?, span: TimeInterval, plotWidth: CGFloat) -> TimeInterval`
  - `static let targetShortestBarWidth: CGFloat = 24`
  - `func zoomed(by factor: Double) -> WaterfallWindow`
  - `func movedToCentre(_ time: TimeInterval) -> WaterfallWindow`
  - `func centred(on time: TimeInterval, duration: TimeInterval) -> WaterfallWindow`
  - `func contains(start: TimeInterval, duration: TimeInterval) -> Bool`
  - `var canZoom: Bool`, `var end: TimeInterval`, `var centre: TimeInterval`, `var startFraction: Double`, `var durationFraction: Double`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/WaterfallWindowTests.swift`:

```swift
//
//  WaterfallWindowTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers every rule about what slice of the log is visible. These are the rules the pinch
/// gesture cannot be trusted to enforce, which is why they live in a value type rather than in
/// the view: a gesture is not unit-testable and this is.
final class WaterfallWindowTests: XCTestCase {

    func testTheWidestWindowIsTheWholeSpan() {
        let window = WaterfallWindow(span: 60, narrowest: 0.5)
        XCTAssertEqual(window.start, 0)
        XCTAssertEqual(window.duration, 60)
    }

    func testZoomingInHoldsTheCentreStill() {
        let window = WaterfallWindow(start: 20, duration: 20, span: 60, narrowest: 0.5)
        let zoomed = window.zoomed(by: 2)

        XCTAssertEqual(zoomed.duration, 10, accuracy: 0.0001)
        XCTAssertEqual(zoomed.centre, 30, accuracy: 0.0001,
                       "pinching changes resolution, not position")
    }

    func testZoomingCannotGoNarrowerThanTheLimit() {
        let window = WaterfallWindow(start: 0, duration: 60, span: 60, narrowest: 2)
        XCTAssertEqual(window.zoomed(by: 1_000).duration, 2, accuracy: 0.0001)
    }

    func testZoomingCannotGoWiderThanTheSpan() {
        let window = WaterfallWindow(start: 20, duration: 10, span: 60, narrowest: 2)
        let zoomed = window.zoomed(by: 0.001)

        XCTAssertEqual(zoomed.duration, 60, accuracy: 0.0001)
        XCTAssertEqual(zoomed.start, 0, accuracy: 0.0001)
    }

    /// Zooming out at the right-hand end has to pull the window back rather than let it hang off
    /// the end of the log, which would show time that does not exist.
    func testZoomingOutAtTheEndPullsTheWindowBackInsteadOfOverhanging() {
        let window = WaterfallWindow(start: 55, duration: 5, span: 60, narrowest: 1)
        let zoomed = window.zoomed(by: 0.25)

        XCTAssertEqual(zoomed.duration, 20, accuracy: 0.0001)
        XCTAssertEqual(zoomed.start, 40, accuracy: 0.0001)
        XCTAssertEqual(zoomed.end, 60, accuracy: 0.0001)
    }

    func testMovingClampsToTheSpanAtBothEnds() {
        let window = WaterfallWindow(start: 20, duration: 10, span: 60, narrowest: 1)

        XCTAssertEqual(window.movedToCentre(-100).start, 0, accuracy: 0.0001)
        XCTAssertEqual(window.movedToCentre(1_000).start, 50, accuracy: 0.0001)
        XCTAssertEqual(window.movedToCentre(30).start, 25, accuracy: 0.0001)
    }

    func testAnEntryStartingBeforeTheWindowAndEndingInsideItIsContained() {
        let window = WaterfallWindow(start: 10, duration: 10, span: 60, narrowest: 1)
        XCTAssertTrue(window.contains(start: 5, duration: 8),
                      "a request already in flight when the window opens is in the window")
        XCTAssertTrue(window.contains(start: 18, duration: 30),
                      "a request that outlives the window is in the window")
        XCTAssertFalse(window.contains(start: 0, duration: 3))
        XCTAssertFalse(window.contains(start: 40, duration: 3))
    }

    /// A zero-length request at the window's edge is still something that happened there.
    func testAZeroLengthEntryOnTheEdgeIsContained() {
        let window = WaterfallWindow(start: 10, duration: 10, span: 60, narrowest: 1)
        XCTAssertTrue(window.contains(start: 10, duration: 0))
        XCTAssertTrue(window.contains(start: 20, duration: 0))
    }

    // MARK: - The narrowest duration

    func testTheNarrowestWindowMakesTheShortestRequestLegible() {
        // 20ms drawn at 24pt across a 240pt plot => a 0.2s window.
        let narrowest = WaterfallWindow.narrowestDuration(shortestMeasured: 0.02,
                                                          span: 60,
                                                          plotWidth: 240)
        XCTAssertEqual(narrowest, 0.2, accuracy: 0.0001)
    }

    func testASeriesWhoseShortestRequestIsAlreadyLegibleCannotZoom() {
        let narrowest = WaterfallWindow.narrowestDuration(shortestMeasured: 30,
                                                          span: 60,
                                                          plotWidth: 240)
        XCTAssertEqual(narrowest, 60, "there is nothing left to magnify")
        XCTAssertFalse(WaterfallWindow(span: 60, narrowest: narrowest).canZoom)
    }

    func testASeriesWithNothingMeasuredCannotZoom() {
        let narrowest = WaterfallWindow.narrowestDuration(shortestMeasured: nil,
                                                          span: 60,
                                                          plotWidth: 240)
        XCTAssertEqual(narrowest, 60)
    }

    func testAnEmptySeriesProducesAWindowThatDoesNotDivideByZero() {
        let window = WaterfallWindow(span: 0, narrowest: 0)
        XCTAssertEqual(window.duration, 0)
        XCTAssertFalse(window.canZoom)
        XCTAssertEqual(window.startFraction, 0)
        XCTAssertEqual(window.durationFraction, 1)
        XCTAssertEqual(window.zoomed(by: 4), window)
    }

    // MARK: - Opening centred

    func testOpeningCentredOnATimeClampsIntoTheSpan() {
        let widest = WaterfallWindow(span: 80, narrowest: 1)
        let opened = widest.centred(on: 2, duration: 10)

        XCTAssertEqual(opened.duration, 10, accuracy: 0.0001)
        XCTAssertEqual(opened.start, 0, accuracy: 0.0001,
                       "a tap near the start opens at the start, not before it")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/WaterfallWindowTests`

Expected: FAIL to compile — the type does not exist. Report this as a compile failure, not an assertion failure.

- [ ] **Step 3: Write the implementation**

Create `Sources/Scyther/Features/TrafficStats/WaterfallWindow.swift`:

```swift
//
//  WaterfallWindow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import CoreGraphics
import Foundation

/// The slice of a ``WaterfallSeries`` the page is currently showing.
///
/// Every rule about what can be seen lives here: how far you may zoom in, how far out, where the
/// window may sit, and which entries fall inside it. None of it lives in the view.
///
/// That split is deliberate and it is the whole reason this type exists. Zoom is driven by a
/// pinch, and a gesture cannot be unit-tested honestly — so the gesture is reduced to handing a
/// magnification factor to ``zoomed(by:)`` and installing whatever comes back. The arithmetic
/// that decides whether that is legal is here, where a test can drive it.
///
/// The window carries its own limits rather than taking them per call, so a window can never be
/// combined with the wrong series' span.
///
/// ## Topics
///
/// ### Creating a Window
/// - ``init(span:narrowest:)``
/// - ``init(start:duration:span:narrowest:)``
/// - ``narrowestDuration(shortestMeasured:span:plotWidth:)``
///
/// ### Moving and Zooming
/// - ``zoomed(by:)``
/// - ``movedToCentre(_:)``
/// - ``centred(on:duration:)``
///
/// ### Reading It
/// - ``contains(start:duration:)``
/// - ``canZoom``
struct WaterfallWindow: Equatable, Sendable {

    /// How wide the shortest measured request should be drawn at maximum zoom, in points.
    ///
    /// Past this there is nothing left to magnify: every bar is already legible and the only
    /// thing that grows is the gap between them.
    static let targetShortestBarWidth: CGFloat = 24

    /// Seconds from the series origin to the window's left edge.
    let start: TimeInterval

    /// How many seconds the window spans.
    let duration: TimeInterval

    /// The series' full span — the widest this window may ever be.
    let span: TimeInterval

    /// The tightest duration this window may be narrowed to.
    let narrowest: TimeInterval

    /// The widest window: the whole series.
    ///
    /// - Parameters:
    ///   - span: The series' span.
    ///   - narrowest: The tightest allowed duration, from
    ///     ``narrowestDuration(shortestMeasured:span:plotWidth:)``.
    init(span: TimeInterval, narrowest: TimeInterval) {
        self.init(start: 0, duration: span, span: span, narrowest: narrowest)
    }

    /// A window clamped into `span`.
    ///
    /// Clamping happens here rather than at each call site, so there is exactly one place that
    /// can be wrong about it.
    ///
    /// - Parameters:
    ///   - start: The requested left edge, in seconds from the origin.
    ///   - duration: The requested width, in seconds.
    ///   - span: The series' span.
    ///   - narrowest: The tightest allowed duration.
    init(start: TimeInterval, duration: TimeInterval, span: TimeInterval, narrowest: TimeInterval) {
        let safeSpan = max(0, span.isFinite ? span : 0)
        let safeNarrowest = min(max(0, narrowest.isFinite ? narrowest : safeSpan), safeSpan)
        let width = min(max(duration.isFinite ? duration : safeSpan, safeNarrowest), safeSpan)
        self.span = safeSpan
        self.narrowest = safeNarrowest
        self.duration = width
        self.start = min(max(0, start.isFinite ? start : 0), max(0, safeSpan - width))
    }

    /// Seconds from the origin to the window's right edge.
    var end: TimeInterval { start + duration }

    /// Seconds from the origin to the middle of the window.
    var centre: TimeInterval { start + duration / 2 }

    /// Whether zooming does anything at all.
    ///
    /// `false` for an empty series, a single request, and a series whose shortest request is
    /// already legible at full span. The page disables the gesture rather than letting a pinch
    /// do nothing, because a control that silently ignores you is worse than one that is absent.
    var canZoom: Bool { span > 0 && narrowest < span }

    /// Where the window's left edge sits as a fraction of the span, for drawing the overlay.
    /// `0` when there is no span to be a fraction of.
    var startFraction: Double { span > 0 ? start / span : 0 }

    /// How wide the window is as a fraction of the span, for drawing the overlay. `1` when there
    /// is no span, so an empty strip draws a full-width window rather than an invisible one.
    var durationFraction: Double { span > 0 ? duration / span : 1 }

    /// The tightest window that still leaves the shortest request legible.
    ///
    /// A request of length `d` drawn in a window of length `w` across a plot `p` points wide is
    /// `d / w * p` points. Setting that to ``targetShortestBarWidth`` and solving for `w` gives
    /// `d * p / target`.
    ///
    /// - Parameters:
    ///   - shortestMeasured: The shortest finished, non-zero duration in the series, or `nil`
    ///     when nothing finished. Pending and zero-length requests have no measured length to be
    ///     legible at and must be excluded by the caller.
    ///   - span: The series' span, which is also the answer when no zoom is possible.
    ///   - plotWidth: The width the detail list gives a bar, in points.
    /// - Returns: The tightest allowed duration, never above `span` and never below zero.
    static func narrowestDuration(shortestMeasured: TimeInterval?,
                                  span: TimeInterval,
                                  plotWidth: CGFloat) -> TimeInterval {
        guard span > 0,
              let shortest = shortestMeasured,
              shortest > 0, shortest.isFinite,
              plotWidth > 0 else { return max(0, span) }
        let demanded = shortest * Double(plotWidth) / Double(targetShortestBarWidth)
        guard demanded.isFinite else { return span }
        return min(max(0, demanded), span)
    }

    /// The window magnified by `factor`, holding its centre still.
    ///
    /// Holding the centre is what stops a pinch sliding the developer through time while they are
    /// trying to change resolution.
    ///
    /// - Parameter factor: Greater than 1 zooms in, between 0 and 1 zooms out. A non-finite or
    ///   non-positive factor returns the window unchanged, because a gesture in an odd state must
    ///   not be able to produce a nonsense window.
    /// - Returns: The zoomed window, clamped at both limits and re-clamped into the span.
    func zoomed(by factor: Double) -> WaterfallWindow {
        guard factor.isFinite, factor > 0, span > 0 else { return self }
        let held = centre
        let width = duration / factor
        return WaterfallWindow(start: held - width / 2,
                               duration: width,
                               span: span,
                               narrowest: narrowest)
    }

    /// The window moved so its centre sits at `time`, clamped into the span.
    ///
    /// - Parameter time: Seconds from the origin.
    func movedToCentre(_ time: TimeInterval) -> WaterfallWindow {
        WaterfallWindow(start: time - duration / 2,
                        duration: duration,
                        span: span,
                        narrowest: narrowest)
    }

    /// A window of `duration` centred on `time`, clamped into the span and the zoom limits.
    ///
    /// This is how the page opens when it is reached by tapping the Traffic Stats strip: the tap
    /// names a moment, and the page arrives looking at it.
    ///
    /// - Parameters:
    ///   - time: Seconds from the origin.
    ///   - duration: The width to open at.
    func centred(on time: TimeInterval, duration: TimeInterval) -> WaterfallWindow {
        WaterfallWindow(start: time - duration / 2,
                        duration: duration,
                        span: span,
                        narrowest: narrowest)
    }

    /// Whether an entry's span intersects the window's.
    ///
    /// Intersection, not containment: a request already in flight when the window opens, or one
    /// that outlives it, is part of what was happening in that window and is drawn clipped. Only
    /// requests entirely before or entirely after it are absent.
    ///
    /// - Parameters:
    ///   - start: The entry's start, in seconds from the origin.
    ///   - duration: The entry's length in seconds. Zero is allowed: a zero-length request on the
    ///     edge still happened there.
    func contains(start entryStart: TimeInterval, duration entryDuration: TimeInterval) -> Bool {
        entryStart <= end && entryStart + max(0, entryDuration) >= start
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Scyther -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:ScytherTests/WaterfallWindowTests`

Expected: PASS, all fourteen.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/WaterfallWindow.swift \
        Tests/ScytherTests/Features/WaterfallWindowTests.swift
git commit -m "Add the waterfall's visible time window

Every rule about what can be seen — the zoom limits, the clamping, which
entries fall inside — in a value type rather than in the view. Zoom is driven
by a pinch and a gesture cannot be tested honestly, so the gesture is reduced
to handing a factor in and installing what comes back."
```

---

### Task 3: The overview strip

**Files:**
- Create: `Sources/Scyther/Features/TrafficStats/WaterfallOverviewStrip.swift`
- Test: `Tests/ScytherTests/Features/WaterfallOverviewStripTests.swift`

**Interfaces:**
- Consumes: `WaterfallSeries`, `WaterfallEntry` (Task 1), `WaterfallWindow` (Task 2), `WaterfallChartStyle.colour(for:)`.
- Produces:
  - `struct WaterfallOverviewStrip: View` with
    `init(series: WaterfallSeries, window: WaterfallWindow?, height: CGFloat, onScrub: ((TimeInterval) -> Void)?)`
  - `enum WaterfallStripGeometry` with
    `static func barRect(index: Int, count: Int, start: TimeInterval, duration: TimeInterval, span: TimeInterval, size: CGSize) -> CGRect`
    and `static let maximumBarHeight: CGFloat = 3`, `static let minimumBarWidth: CGFloat = 1`
  - `static let pageHeight: CGFloat = 96`, `static let sectionHeight: CGFloat = 72`

`onScrub` receives a time in seconds from the origin. The page passes a closure that moves its window; Traffic Stats passes one that navigates. `window` is `nil` in Traffic Stats, which is what suppresses the overlay.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ScytherTests/Features/WaterfallOverviewStripTests.swift`:

```swift
//
//  WaterfallOverviewStripTests.swift
//  ScytherTests
//

@testable import Scyther
import CoreGraphics
import XCTest

/// The strip draws in a `Canvas`, which a unit test cannot inspect. Its geometry is therefore a
/// pure function, and this is what proves the drawing is right — the `Canvas` only fills the
/// rects this returns.
final class WaterfallOverviewStripTests: XCTestCase {

    private let size = CGSize(width: 300, height: 90)

    func testABarSitsAtItsShareOfTheSpan() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 10,
                                                  start: 15, duration: 30, span: 60,
                                                  size: size)
        XCTAssertEqual(rect.minX, 75, accuracy: 0.001)
        XCTAssertEqual(rect.width, 150, accuracy: 0.001)
    }

    func testRowsAreStackedDownTheStrip() {
        let first = WaterfallStripGeometry.barRect(index: 0, count: 3, start: 0, duration: 1,
                                                   span: 60, size: size)
        let last = WaterfallStripGeometry.barRect(index: 2, count: 3, start: 0, duration: 1,
                                                  span: 60, size: size)
        XCTAssertLessThan(first.minY, last.minY)
        XCTAssertLessThanOrEqual(last.maxY, size.height)
    }

    /// A 20ms request in a 60s log is a third of a pixel. It has to remain a dot: the strip's
    /// whole job is showing that something happened there.
    func testAVeryShortRequestKeepsAMinimumWidth() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 10,
                                                  start: 10, duration: 0.02, span: 60,
                                                  size: size)
        XCTAssertEqual(rect.width, WaterfallStripGeometry.minimumBarWidth, accuracy: 0.001)
    }

    func testBarsThinAsTheyGetMoreNumerousButNeverVanish() {
        let few = WaterfallStripGeometry.barRect(index: 0, count: 5, start: 0, duration: 1,
                                                 span: 60, size: size)
        let many = WaterfallStripGeometry.barRect(index: 0, count: 500, start: 0, duration: 1,
                                                  span: 60, size: size)
        XCTAssertEqual(few.height, WaterfallStripGeometry.maximumBarHeight, accuracy: 0.001,
                       "a short log should not draw hairlines")
        XCTAssertGreaterThanOrEqual(many.height, 1)
        XCTAssertLessThan(many.height, few.height)
    }

    func testABarNeverLeavesTheStrip() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 1,
                                                  start: 55, duration: 30, span: 60,
                                                  size: size)
        XCTAssertLessThanOrEqual(rect.maxX, size.width + 0.001)
    }

    func testAZeroSpanDoesNotDivideByZero() {
        let rect = WaterfallStripGeometry.barRect(index: 0, count: 1,
                                                  start: 0, duration: 0, span: 0,
                                                  size: size)
        XCTAssertTrue(rect.width.isFinite)
        XCTAssertTrue(rect.minX.isFinite)
        XCTAssertTrue(rect.minY.isFinite)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/WaterfallOverviewStripTests`. Expected: compile failure — `WaterfallStripGeometry` does not exist.

- [ ] **Step 3: Write the geometry and the view**

Create `Sources/Scyther/Features/TrafficStats/WaterfallOverviewStrip.swift`:

```swift
//
//  WaterfallOverviewStrip.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import SwiftUI

/// Where each request is drawn on the overview strip.
///
/// Separated from the view because a `Canvas` cannot be inspected by a test. The `Canvas` fills
/// exactly the rects this returns and does nothing else, so testing this tests the drawing.
enum WaterfallStripGeometry {

    /// The tallest a single request's line is drawn, in points.
    ///
    /// A log of five requests drawn as hairlines looks broken; a log of five hundred drawn at
    /// three points would not fit. The height is the smaller of this and an even share.
    static let maximumBarHeight: CGFloat = 3

    /// The narrowest a request is drawn, in points.
    ///
    /// A 20ms request inside a 60s log is a third of a pixel wide. The strip exists to show that
    /// something happened at that moment, so it stays a visible dot.
    static let minimumBarWidth: CGFloat = 1

    /// Where one request is drawn.
    ///
    /// - Parameters:
    ///   - index: The request's position in the series, oldest first.
    ///   - count: How many requests the series holds.
    ///   - start: The request's start, in seconds from the origin.
    ///   - duration: The request's length in seconds.
    ///   - span: The series' span in seconds.
    ///   - size: The strip's size in points.
    /// - Returns: The rect to fill, always inside `size`.
    static func barRect(index: Int,
                        count: Int,
                        start: TimeInterval,
                        duration: TimeInterval,
                        span: TimeInterval,
                        size: CGSize) -> CGRect {
        guard count > 0, size.width > 0, size.height > 0 else { return .zero }

        let usableSpan = span > 0 && span.isFinite ? span : 1
        let x = CGFloat(min(max(0, start / usableSpan), 1)) * size.width
        let rawWidth = CGFloat(max(0, duration) / usableSpan) * size.width
        let width = min(max(rawWidth, minimumBarWidth), max(0, size.width - x))

        let height = min(maximumBarHeight, max(1, size.height / CGFloat(count)))
        let lane = (size.height - height) / CGFloat(max(1, count - 1))
        let y = count == 1 ? (size.height - height) / 2 : CGFloat(index) * lane

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// The whole log compressed into one strip: every request as a short horizontal line, placed by
/// when it happened and coloured by how it went.
///
/// One view, two jobs. On ``WaterfallView`` it carries the current window as an overlay and takes
/// a drag that moves it. In ``TrafficStatsView`` it carries no window and a tap opens the page at
/// the moment touched.
///
/// Drawn with a `Canvas` rather than a stack of shapes. Both callers now build from the entire
/// log rather than the most recent handful, and a view per request would be thousands of views
/// for a busy session; a `Canvas` is one drawing pass whatever the count.
struct WaterfallOverviewStrip: View {

    /// The strip's height on the full page, in points.
    static let pageHeight: CGFloat = 96

    /// The strip's height inside the Traffic Stats section, in points. Shorter because it is one
    /// section among several rather than the screen's subject.
    static let sectionHeight: CGFloat = 72

    /// The log to draw.
    let series: WaterfallSeries

    /// The window to mark, or `nil` to draw no overlay.
    let window: WaterfallWindow?

    /// The strip's height.
    let height: CGFloat

    /// What to do when the strip is touched, given a time in seconds from the series origin.
    let onScrub: ((TimeInterval) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for (index, entry) in series.entries.enumerated() {
                        let rect = WaterfallStripGeometry.barRect(
                            index: index,
                            count: series.entries.count,
                            start: entry.start,
                            duration: entry.duration,
                            span: series.span,
                            size: size
                        )
                        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2),
                                     with: .color(WaterfallChartStyle.colour(for: entry)))
                    }
                }
                if let window, window.span > 0 {
                    Rectangle()
                        .fill(WaterfallChartStyle.windowTint)
                        .frame(width: max(2, proxy.size.width * window.durationFraction))
                        .overlay(alignment: .leading) { edge }
                        .overlay(alignment: .trailing) { edge }
                        .offset(x: proxy.size.width * window.startFraction)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrub(width: proxy.size.width))
        }
        .frame(height: height)
        .background(WaterfallChartStyle.stripBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel(localized("Traffic overview"))
    }

    /// The window overlay's edge rule, on both sides, so the window reads as a frame rather than
    /// as a tint that might be a highlight.
    private var edge: some View {
        Rectangle()
            .fill(WaterfallChartStyle.windowEdge)
            .frame(width: 2)
    }

    /// Turns a touch anywhere on the strip into a time.
    ///
    /// `minimumDistance` is zero so a tap counts, which is what Traffic Stats needs; the page
    /// gets dragging from the same gesture for free.
    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let onScrub, width > 0, series.span > 0 else { return }
                let fraction = min(max(0, value.location.x / width), 1)
                onScrub(Double(fraction) * series.span)
            }
    }
}
```

- [ ] **Step 4: Add the three style values**

In `WaterfallChartStyle.swift`, beside the existing colours:

```swift
    /// The tint filling the overview strip's current window.
    ///
    /// Low alpha on the success colour: the window is a frame around what you are reading, not a
    /// status, so it must not read as one of the four states the bars use.
    static let windowTint = Color.green.opacity(0.14)

    /// The rules on the window's left and right edges.
    static let windowEdge = Color.green.opacity(0.9)

    /// The strip's own ground, so the compressed bars have something to sit on.
    static let stripBackground = Color.primary.opacity(0.06)
```

`WaterfallChartStyle.colour(for entry: WaterfallEntry) -> Color` already exists at `WaterfallChartStyle.swift:264` — British spelling, as the rest of this file is. Use it; do not add a `color` alias.

- [ ] **Step 5: Add the localisation key**

Add `"Traffic overview"` to `Scripts/localization/strings/TrafficStats.json` with all twelve languages, then:

```bash
python3 Scripts/localization/build_catalog.py
```

- [ ] **Step 6: Run the tests**

Run with `-only-testing:ScytherTests/WaterfallOverviewStripTests`, then the full suite. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/WaterfallOverviewStrip.swift \
        Sources/Scyther/Features/TrafficStats/WaterfallChartStyle.swift \
        Sources/Scyther/Resources/Localizable.xcstrings \
        Scripts/localization/strings/TrafficStats.json \
        Tests/ScytherTests/Features/WaterfallOverviewStripTests.swift
git commit -m "Draw the whole log as one overview strip

A Canvas rather than a view per request: both callers now build from the entire
log, and a busy session is thousands of bars. The geometry is a pure function
because a Canvas cannot be inspected by a test."
```

---

### Task 4: The view model owns the window

**Files:**
- Modify: `Sources/Scyther/Features/TrafficStats/WaterfallViewModel.swift`
- Test: `Tests/ScytherTests/Features/WaterfallViewModelTests.swift`

**Interfaces:**
- Consumes: `WaterfallWindow` (Task 2), `WaterfallEntry.shortHost` (Task 1), the existing `Layout`/`Row` types.
- Produces, on `WaterfallViewModel`:
  - `@Published private(set) var window: WaterfallWindow`
  - `var visibleRows: [Row]`
  - `func configureWindow(plotWidth: CGFloat)` — recomputes limits, keeps the current centre
  - `func zoom(by factor: Double)`
  - `func scrub(to time: TimeInterval)`
  - `func open(centredOn time: TimeInterval)`
  - `var windowCaption: String`
  - `var isWindowEmpty: Bool`
  - `static let openingWindowFraction: Double = 1.0 / 8.0`

`Layout` gains `shortestMeasured: Double?` alongside its existing `medianDuration` and
`tailDuration`, computed in the same detached pass and cached for the same reason.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ScytherTests/Features/WaterfallViewModelTests.swift` (create it if it does not exist, matching the header style of the other test files in that directory):

```swift
    // MARK: - The window

    /// Builds a view model over requests at known offsets, each lasting `duration` seconds.
    @MainActor
    private func makeModel(starts: [TimeInterval], duration: TimeInterval = 0.05)
        -> WaterfallViewModel {
        let origin = Date(timeIntervalSince1970: 1_000)
        let requests: [HTTPRequest] = starts.map { offset in
            let request = HTTPRequest()
            request.requestURL = "https://api.ipify.org/?format=json"
            request.requestMethod = "GET"
            request.requestDate = origin.addingTimeInterval(offset)
            request.responseDate = origin.addingTimeInterval(offset + duration)
            return request
        }
        let model = WaterfallViewModel()
        model.update(requests: requests, totalCount: requests.count)
        return model
    }

    @MainActor
    func testThePageOpensShowingTheWholeSpan() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)

        XCTAssertEqual(model.window.start, 0, accuracy: 0.0001)
        XCTAssertEqual(model.window.duration, model.series.span, accuracy: 0.0001,
                       "the page opens honest, and zoom is the escape")
        XCTAssertEqual(model.visibleRows.count, 4)
    }

    @MainActor
    func testZoomingDropsTheRowsThatLeaveTheWindow() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.scrub(to: 0)
        model.zoom(by: 8)

        XCTAssertLessThan(model.visibleRows.count, 4)
        XCTAssertTrue(model.visibleRows.allSatisfy {
            model.window.contains(start: $0.entry.start, duration: $0.entry.duration)
        })
    }

    @MainActor
    func testScrubbingMovesTheWindowToTheTimeTouched() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 8)
        model.scrub(to: 20)

        XCTAssertEqual(model.window.centre, 20, accuracy: 0.5)
    }

    /// Dragging into a stretch with no traffic must say so rather than showing a blank list.
    @MainActor
    func testAWindowOverAGapReportsItselfEmpty() async {
        let model = makeModel(starts: [0, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 20)
        model.scrub(to: 15)

        XCTAssertTrue(model.visibleRows.isEmpty)
        XCTAssertTrue(model.isWindowEmpty)
    }

    @MainActor
    func testASingleRequestCannotZoom() async {
        let model = makeModel(starts: [0])
        await model.recompute()
        model.configureWindow(plotWidth: 240)

        XCTAssertFalse(model.window.canZoom)
    }

    @MainActor
    func testOpeningCentredOnATimeUsesAnEighthOfTheSpan() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.open(centredOn: 20)

        XCTAssertEqual(model.window.duration,
                       model.series.span * WaterfallViewModel.openingWindowFraction,
                       accuracy: 0.01)
        XCTAssertEqual(model.window.centre, 20, accuracy: 0.5)
    }

    /// Re-measuring the plot must not throw away where the developer had scrolled to.
    @MainActor
    func testReconfiguringForANewWidthKeepsTheCentre() async {
        let model = makeModel(starts: [0, 10, 20, 30])
        await model.recompute()
        model.configureWindow(plotWidth: 240)
        model.zoom(by: 4)
        model.scrub(to: 20)
        let centre = model.window.centre

        model.configureWindow(plotWidth: 180)

        XCTAssertEqual(model.window.centre, centre, accuracy: 0.5)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run with `-only-testing:ScytherTests/WaterfallViewModelTests`. Expected: compile failure — `window`, `configureWindow(plotWidth:)`, `zoom(by:)`, `scrub(to:)`, `open(centredOn:)`, `visibleRows` and `isWindowEmpty` do not exist. Report it as a compile failure.

- [ ] **Step 3: Cache the shortest measured duration**

In `WaterfallViewModel.Layout`, after `tailDuration`:

```swift
        /// The shortest finished, non-zero duration in the series, or `nil` when nothing
        /// finished.
        ///
        /// Cached beside the median and the tail, and for the same reason: it is an input to the
        /// zoom limit, the view recomputes that whenever its geometry changes, and a `List` asks
        /// for geometry constantly.
        let shortestMeasured: Double?
```

Add `shortestMeasured: nil` to `Layout.empty`, and in the detached computation, beside where `durations` is already taken:

```swift
        let shortestMeasured = durations.filter { $0 > 0 }.min()
```

passing it into the `Layout(...)` initialiser.

- [ ] **Step 4: Add the window to the view model**

```swift
    /// How much of the span the page opens with when it is reached by tapping the Traffic Stats
    /// strip.
    ///
    /// An eighth is wide enough to carry context around the moment tapped and narrow enough to be
    /// worth the navigation. Opening at the narrowest allowed window would be well defined and
    /// could land the developer inside a tenth of a second.
    static let openingWindowFraction: Double = 1.0 / 8.0

    /// The slice of the log the page is showing.
    ///
    /// Published rather than derived so the strip's overlay and the detail list are always
    /// drawing the same window: two views deriving it separately is two views one layout pass
    /// apart from disagreeing.
    @Published private(set) var window: WaterfallWindow = WaterfallWindow(span: 0, narrowest: 0)

    /// The width the detail list gives a bar, from the last ``configureWindow(plotWidth:)``.
    private var plotWidth: CGFloat = WaterfallChartStyle.minimumPlotWidth

    /// The rows the window holds, oldest first.
    ///
    /// Intersection rather than containment, so a request already in flight when the window opens
    /// is shown clipped rather than missing. See ``WaterfallWindow/contains(start:duration:)``.
    var visibleRows: [Row] {
        layout.rows.filter { window.contains(start: $0.entry.start, duration: $0.entry.duration) }
    }

    /// Whether the window is over a stretch of the log with no traffic in it.
    ///
    /// Distinct from an empty log, which the page answers with its `ContentUnavailableView`. This
    /// one earns a row saying so, because a blank list after a drag reads as a bug.
    var isWindowEmpty: Bool { !layout.rows.isEmpty && visibleRows.isEmpty }

    /// Recomputes the zoom limits for a plot of `plotWidth`, keeping the current centre.
    ///
    /// Called whenever the list's geometry changes. Keeping the centre matters because a rotation
    /// or a Dynamic Type change re-measures the plot, and throwing the developer back to the
    /// start of the log because the row got narrower would be its own bug.
    ///
    /// - Parameter plotWidth: The width a bar is drawn across, in points.
    func configureWindow(plotWidth: CGFloat) {
        self.plotWidth = max(WaterfallChartStyle.minimumPlotWidth, plotWidth)
        let span = layout.series.span
        let narrowest = WaterfallWindow.narrowestDuration(
            shortestMeasured: layout.shortestMeasured,
            span: span,
            plotWidth: self.plotWidth
        )
        let previousCentre = window.span > 0 ? window.centre : span / 2
        let previousDuration = window.span > 0 ? window.duration : span
        window = WaterfallWindow(start: previousCentre - previousDuration / 2,
                                 duration: previousDuration,
                                 span: span,
                                 narrowest: narrowest)
    }

    /// Magnifies the window, holding its centre.
    ///
    /// - Parameter factor: The pinch's magnitude. Above 1 zooms in.
    func zoom(by factor: Double) {
        guard window.canZoom else { return }
        window = window.zoomed(by: factor)
    }

    /// Moves the window's centre to `time`.
    ///
    /// - Parameter time: Seconds from the series origin.
    func scrub(to time: TimeInterval) {
        window = window.movedToCentre(time)
    }

    /// Opens the window at ``openingWindowFraction`` of the span, centred on `time`.
    ///
    /// - Parameter time: Seconds from the series origin.
    func open(centredOn time: TimeInterval) {
        let span = layout.series.span
        guard span > 0 else { return }
        window = window.centred(on: time, duration: span * Self.openingWindowFraction)
    }

    /// What the page says under the list about what is on screen.
    var windowCaption: String {
        localized("\(visibleRows.count) of \(layout.total) requests")
    }
```

At the end of `recompute()`, after `layout` is assigned, re-derive the window against the new series:

```swift
        configureWindow(plotWidth: plotWidth)
```

- [ ] **Step 5: Add the localisation key**

Add `"%lld of %lld requests"` to `Scripts/localization/strings/TrafficStats.json` in all twelve languages with correct plural categories, then run `python3 Scripts/localization/build_catalog.py`.

- [ ] **Step 6: Run the tests**

Run with `-only-testing:ScytherTests/WaterfallViewModelTests`, then the full suite. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/WaterfallViewModel.swift \
        Sources/Scyther/Resources/Localizable.xcstrings \
        Scripts/localization/strings/TrafficStats.json \
        Tests/ScytherTests/Features/WaterfallViewModelTests.swift
git commit -m "Give the waterfall view model a window

Published rather than derived, so the strip's overlay and the detail list can
never be a layout pass apart on which slice of time they are drawing."
```

---

### Task 5: Rewrite the page

**Files:**
- Modify: `Sources/Scyther/Features/TrafficStats/WaterfallView.swift`

**Interfaces:**
- Consumes: `WaterfallOverviewStrip` (Task 3), everything added to `WaterfallViewModel` in Task 4.
- Produces: nothing later tasks consume.

- [ ] **Step 1: Replace the body**

The page becomes, in order: the legend as it is today, the strip, the detail list, the caption. Remove the frozen label column, the two-axis `ScrollView`, and the ruler pinned inside it.

```swift
    var body: some View {
        VStack(spacing: 0) {
            legend
            WaterfallOverviewStrip(series: viewModel.series,
                                   window: viewModel.window,
                                   height: WaterfallOverviewStrip.pageHeight,
                                   onScrub: { viewModel.scrub(to: $0) })
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: viewModel.zoom(by: 2)
                    case .decrement: viewModel.zoom(by: 0.5)
                    @unknown default: break
                    }
                }
            detail
            Text(viewModel.windowCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle(localized("Waterfall"))
    }
```

`.accessibilityAdjustableAction` on the strip is what keeps zoom reachable without a pinch. VoiceOver and Switch Control users get the same range; the toolkit does not get to ship an accessibility audit one release and a gesture-only control the next.

- [ ] **Step 2: Write the detail list**

```swift
    /// The rows the window holds.
    ///
    /// A `List` rather than a `LazyVStack` in a `ScrollView`: rows are `NavigationLink`s and this
    /// is a menu screen, so it takes the menu's row treatment, separators and press states for
    /// free rather than hand-rolling them.
    @ViewBuilder
    private var detail: some View {
        GeometryReader { proxy in
            List {
                if viewModel.isWindowEmpty {
                    Text(localized("No requests in this part of the log."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.visibleRows) { row in
                        NavigationLink {
                            LogDetailsView(httpRequest: row.request)
                        } label: {
                            WaterfallDetailRow(row: row, window: viewModel.window)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onAppear { viewModel.configureWindow(plotWidth: plotWidth(in: proxy.size.width)) }
            .onChange(of: proxy.size.width) { _ in
                viewModel.configureWindow(plotWidth: plotWidth(in: proxy.size.width))
            }
            .gesture(magnification, including: .all)
        }
    }

    /// The width a bar actually gets, which is the row less the label and duration columns.
    ///
    /// The zoom limit is computed from this rather than from the screen's width, so the shortest
    /// request really is 24pt at maximum zoom instead of 24pt-minus-the-chrome.
    private func plotWidth(in rowWidth: CGFloat) -> CGFloat {
        max(WaterfallChartStyle.minimumPlotWidth,
            rowWidth - WaterfallChartStyle.detailLabelWidth - WaterfallChartStyle.detailDurationWidth - 48)
    }
```

- [ ] **Step 3: Write the pinch**

```swift
    /// The last magnification the gesture reported, so each change applies only the delta.
    ///
    /// `MagnificationGesture` reports magnitude relative to the gesture's start, not to the last
    /// callback. Feeding that straight to `zoom(by:)` would apply the whole pinch again on every
    /// frame and slam into the limit instantly.
    @State private var lastMagnification: CGFloat = 1

    /// Pinch to zoom, running alongside the list's scrolling rather than instead of it.
    ///
    /// `MagnificationGesture` and not `MagnifyGesture`: the package's floor is iOS 16 and
    /// `MagnifyGesture` is iOS 17.
    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard value.isFinite, value > 0, lastMagnification > 0 else { return }
                viewModel.zoom(by: Double(value / lastMagnification))
                lastMagnification = value
            }
            .onEnded { _ in lastMagnification = 1 }
    }
```

- [ ] **Step 4: Write the row**

Create the row as its own small view in the same file, since it exists only for this list:

```swift
/// One request in the waterfall's detail list: who it went to, what it was, when it happened
/// inside the window, and how long it took.
private struct WaterfallDetailRow: View {
    let row: WaterfallViewModel.Row
    let window: WaterfallWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(row.entry.shortHost) · \(row.entry.label)")
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: WaterfallChartStyle.detailLabelWidth, alignment: .leading)

            GeometryReader { proxy in
                let rect = barRect(in: proxy.size)
                RoundedRectangle(cornerRadius: 3)
                    .fill(WaterfallChartStyle.colour(for: row.entry))
                    .frame(width: rect.width, height: 10)
                    .offset(x: rect.minX, y: (proxy.size.height - 10) / 2)
            }

            Text(row.entry.isPending
                 ? localized("—") // scyther:unlocalised em dash for an unfinished request
                 : DurationText.seconds(row.entry.duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: WaterfallChartStyle.detailDurationWidth, alignment: .trailing)
        }
        .frame(height: 44)
    }

    /// The bar's position inside the window, clipped at both edges.
    ///
    /// Clipping rather than shrinking: a request that outlives the window is drawn flush to the
    /// edge, so the clip reads as "continues" instead of as a shorter request than it was.
    private func barRect(in size: CGSize) -> CGRect {
        guard window.duration > 0, size.width > 0 else { return .zero }
        let scale = size.width / CGFloat(window.duration)
        let rawStart = CGFloat(row.entry.start - window.start) * scale
        let rawEnd = CGFloat(row.entry.start + row.entry.duration - window.start) * scale
        let clippedStart = min(max(0, rawStart), size.width)
        let clippedEnd = min(max(0, rawEnd), size.width)
        return CGRect(x: clippedStart,
                      y: 0,
                      width: max(3, clippedEnd - clippedStart),
                      height: 10)
    }
}
```

`DurationText.seconds(_ seconds: TimeInterval) -> String` already exists at `DurationText.swift:51` and returns a formatted string, so wrapping it in `Text` is right.

- [ ] **Step 5: Add the two width constants**

In `WaterfallChartStyle.swift`:

```swift
    /// The detail row's label column, in points.
    static let detailLabelWidth: CGFloat = 132

    /// The detail row's duration column, in points. Sized for "1.25 s" plus a little, which is
    /// what the shipped page clipped.
    static let detailDurationWidth: CGFloat = 62
```

- [ ] **Step 6: Add the localisation keys**

`"No requests in this part of the log."` and `"Traffic overview"` (if not already added in Task 3) go into `Scripts/localization/strings/TrafficStats.json` in all twelve languages. Rebuild the catalogue.

- [ ] **Step 7: Build and run the full suite**

Run the full test command. Expected: no failures. Fix any test that referenced the removed frozen-column or two-axis-scroll behaviour by deleting it — those tests pinned a design that no longer exists, and say so in the commit rather than quietly dropping them.

- [ ] **Step 8: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/WaterfallView.swift \
        Sources/Scyther/Features/TrafficStats/WaterfallChartStyle.swift \
        Sources/Scyther/Resources/Localizable.xcstrings \
        Scripts/localization/strings/TrafficStats.json \
        Tests/
git commit -m "Rebuild the waterfall page around the window

Strip on top, detail list below holding only what the window holds, so a row
without a bar is now impossible rather than merely rarer. Zoom is a pinch, with
an adjustable action so VoiceOver reaches the same range."
```

---

### Task 6: The Traffic Stats section becomes the strip

**Files:**
- Modify: `Sources/Scyther/Features/TrafficStats/TrafficStatsView.swift`
- Modify: `Sources/Scyther/Features/TrafficStats/TrafficStatsViewModel.swift`
- Test: `Tests/ScytherTests/Features/TrafficStatsViewModelTests.swift`

**Interfaces:**
- Consumes: `WaterfallOverviewStrip` (Task 3), `WaterfallViewModel.open(centredOn:)` (Task 4).
- Produces: nothing later tasks consume.

- [ ] **Step 1: Write the failing test**

```swift
    /// The section is a minimap now, so it draws everything rather than the most recent handful.
    @MainActor
    func testTheWaterfallSectionDrawsTheWholeLogRatherThanAPreviewsWorth() async {
        let origin = Date(timeIntervalSince1970: 1_000)
        let requests: [HTTPRequest] = (0..<40).map { index in
            let request = HTTPRequest()
            request.requestURL = "https://httpbin.org/json"
            request.requestMethod = "GET"
            request.requestDate = origin.addingTimeInterval(Double(index))
            request.responseDate = origin.addingTimeInterval(Double(index) + 0.1)
            return request
        }

        let model = TrafficStatsViewModel()
        model.update(requests: requests, totalCount: requests.count)
        await model.recompute()

        XCTAssertEqual(model.waterfall.entries.count, 40,
                       "the strip is an overview of everything, not a sample of it")
    }
```

Adapt the construction to whatever `TrafficStatsViewModel`'s real update entry point is — read the file first.

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL on an assertion — the count comes back as `WaterfallSeries.defaultLimit`, which is 7.

- [ ] **Step 3: Build the section's series from the whole log**

Find where `TrafficStatsViewModel` calls `WaterfallSeries.build(from:)` and pass `limit: requests.count` as the page already does.

- [ ] **Step 4: Replace the section's chart with the strip**

In `TrafficStatsView.swift`, the Waterfall section keeps its header and **See all** link. Replace the bars with:

```swift
                WaterfallOverviewStrip(series: viewModel.waterfall,
                                       window: nil,
                                       height: WaterfallOverviewStrip.sectionHeight,
                                       onScrub: nil)
```

and change the **See all** `NavigationLink` to carry no time — a tap on the *link* opens at full span, which is the page's default. A tap on the *strip* opens centred: give the strip an `onScrub` that stores the time and activates the same destination.

```swift
    /// The moment the strip was tapped, which the page opens centred on.
    @State private var openingTime: TimeInterval?
```

Drive the navigation from a single `NavigationLink(isActive:)` whose destination calls
`viewModel.open(centredOn:)` on the page's view model in `.onAppear` when `openingTime` is set.

- [ ] **Step 5: Update the section's footer**

`TrafficStatsViewModel.waterfallCaption` already exists at `TrafficStatsViewModel.swift:253` and currently describes a preview of the most recent requests. Replace its body — do not add a second caption:

```swift
    /// What the strip is showing, under it.
    var waterfallCaption: String {
        localized("\(waterfall.entries.count) requests over \(DurationText.seconds(waterfall.span)) across \(hostCount) hosts")
    }
```

with

```swift
    /// How many distinct hosts the log touched, for the section's footer.
    ///
    /// The count rather than the names: the names are on the rows, and a section footer listing
    /// twelve hosts is a paragraph.
    var hostCount: Int { Set(waterfall.entries.map(\.host)).filter { !$0.isEmpty }.count }
```

- [ ] **Step 6: Deal with `defaultLimit` and the test that pins it**

`WaterfallSeries.defaultLimit` is `build(from:limit:now:)`'s default argument and two tests pin it, including `WaterfallSeriesTests`' assertion that "a preview has to read as one". That policy is exactly what this design reverses.

Rewrite that test to assert the new policy — that a series built without a limit keeps everything it was given — and delete `defaultLimit` along with `build`'s default argument, making `limit` required. A required parameter is honest here: there is no longer a sensible default, and every caller now knows what it wants.

Update `TrafficStatsViewModelTests`' `defaultLimit` references the same way.

- [ ] **Step 7: Add the localisation key**

`"%lld requests over %@ across %lld hosts"` into `Scripts/localization/strings/TrafficStats.json`, twelve languages, then rebuild the catalogue.

- [ ] **Step 8: Run the full suite and commit**

```bash
git add Sources/Scyther/Features/TrafficStats/ \
        Sources/Scyther/Resources/Localizable.xcstrings \
        Scripts/localization/strings/TrafficStats.json \
        Tests/
git commit -m "Make the Traffic Stats waterfall an overview of everything

It showed the last seven bars, which answered no question the numbers above it
did not. It is now the same strip the page uses, over the whole log, and
tapping it opens the page centred there. defaultLimit and the test asserting a
preview reads as one go with it — that policy is what this reverses."
```

---

### Task 7: Retire the global time scale

**Files:**
- Modify: `Sources/Scyther/Features/TrafficStats/WaterfallTimeScale.swift`
- Modify: `Tests/ScytherTests/Features/WaterfallTimeScaleTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. This task only removes.

- [ ] **Step 1: Find what still uses it**

```bash
grep -rn "WaterfallTimeScale" Sources/ Tests/
```

- [ ] **Step 2: Delete the scale-choosing half**

Remove `pointsPerSecond`, `contentWidth`, `tickInterval`, `upperBound`, `make(medianDuration:tailDuration:span:visibleWidth:)`, `make(for:visibleWidth:)`, `medianBarWidth`, `tailBarWidth`, `maximumContentWidth`, and `minimumTickSpacing`. Those choose one scale for a whole series, which no longer happens.

Keep `measuredDurations(of:)` and `percentile(_:of:)` — the view model still needs the median for the caption and the shortest for the zoom limit. If nothing but those two survive, rename the file to `WaterfallDurations.swift` and the type to match; a type called `TimeScale` that no longer computes a scale is a trap for the next reader.

- [ ] **Step 3: Delete the tests that pinned the removed behaviour**

Every test in `WaterfallTimeScaleTests` asserting points-per-second, the 50,000 pt ceiling, the median-at-24 pt rule, or tick intervals goes. Keep the tests for `measuredDurations(of:)` and `percentile(_:of:)`.

Do not soften these into weaker tests of the new code — the new behaviour is covered by `WaterfallWindowTests`. Deleting a test whose subject no longer exists is correct; leaving a hollowed-out version of it is not.

- [ ] **Step 4: Run the full suite**

Expected: no failures, and a test count lower than before by the number of deleted tests. State that number in your report.

- [ ] **Step 5: Commit**

```bash
git add Sources/Scyther/Features/TrafficStats/ Tests/
git commit -m "Remove the global points-per-second scale

Nothing chooses one scale for a whole series any more — the window does it, per
window. The median and percentile measurements survive because the caption and
the zoom limit still need them."
```

---

### Task 8: Documentation and verification on device

**Files:**
- Modify: `README.md`
- Modify: `Sources/Scyther/Scyther.docc/NetworkDebugging.md` — the article covering network tooling, which is where Traffic Stats and the waterfall are described

**Interfaces:**
- Consumes: everything.
- Produces: nothing.

- [ ] **Step 1: Update the README**

Find the Traffic Stats / waterfall description and rewrite it for what the feature now is: an overview strip of every request with a windowed detail list, pinch to zoom, drag the strip to move, tap through to the log entry. Delete any sentence describing horizontal time-scrolling or a frozen label column.

- [ ] **Step 2: Update the DocC article**

Do the same in `NetworkDebugging.md`, and add a paragraph explaining why the page opens at full span — it is the decision most likely to be "fixed" by someone who has not read the spec.

- [ ] **Step 3: Build the example app**

```bash
cd Example && xcodebuild build -project ScytherExample.xcodeproj -scheme ScytherExample \
  -destination 'platform=iOS Simulator,id=0EEED0FF-A025-468E-9466-3BDE708B41B0' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-waterfall
```

Install and launch it, then generate traffic with **Make Multiple Requests** several times so the log holds a realistic spread.

- [ ] **Step 4: Walk the spec's seven checks**

From the spec's "Verification on device" section, in order. Report what you saw for each, with a screenshot for anything that looks wrong:

1. The page arrives showing the whole span, every row carrying a bar.
2. Pinching in zooms the detail, narrows the strip's window to match, and rows leave the list as they leave the window.
3. Dragging the strip end to end keeps the detail up to date and never empties except over a genuine gap.
4. Zoom stops at both limits rather than continuing to scale.
5. Tapping a row opens that request's log detail.
6. Opening from the Traffic Stats strip arrives centred on the tapped point.
7. With VoiceOver on, the strip's adjustable action zooms.

**Do not report this task done on a build you have not run.** Every serious defect in this feature's history — the hang, the dead rows, the clipped text, the wrong scroll axis — was found by running the app, not by reading the diff or the tests.

- [ ] **Step 5: Commit**

```bash
git add README.md Sources/Scyther/Scyther.docc/
git commit -m "Document the waterfall's overview strip and window"
```

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task: the problem and decisions inform all of them; architecture is Tasks 1–6; the window's limits, default and opening rule are Task 2 and Task 4; the strip is Task 3; the detail list and short host are Tasks 1 and 5; zoom and its accessibility equivalent are Task 5; Traffic Stats is Task 6; "what is removed" is Tasks 5–7; edge cases are spread across Tasks 2, 4 and 5 and re-checked in Task 8; localisation is folded into each task that adds a string; testing is folded into each task; device verification is Task 8.

**Known gap, stated rather than hidden.** The spec's edge case "all requests the same length ⇒ zoom disabled" is covered by `WaterfallWindowTests.testASeriesWhoseShortestRequestIsAlreadyLegibleCannotZoom` at the window level, but no test drives it through the view model. Task 4's implementer should add one if it is cheap; it is not worth a task of its own.

**Type consistency.** `WaterfallWindow`'s members are used with the same names in Tasks 3, 4 and 5 (`startFraction`, `durationFraction`, `canZoom`, `contains(start:duration:)`, `centre`, `span`). `WaterfallViewModel`'s additions are used with the same names in Tasks 5 and 6 (`window`, `visibleRows`, `isWindowEmpty`, `configureWindow(plotWidth:)`, `zoom(by:)`, `scrub(to:)`, `open(centredOn:)`, `windowCaption`). `WaterfallOverviewStrip`'s initialiser is called identically in Tasks 5 and 6.

**Two names to verify before use, not invent.** `WaterfallChartStyle.colour(for:)` and `DurationText`'s formatting entry point are both referenced from memory of the existing code. Tasks 3 and 5 say to read the file and use the real name rather than adding an alias to match this plan.
