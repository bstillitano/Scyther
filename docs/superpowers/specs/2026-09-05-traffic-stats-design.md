# Traffic Stats and Waterfall

**Date:** 2026-09-05
**Status:** Approved design — ready for implementation planning
**Part:** 4 of 4 in the networking backlog
**Depends on:** nothing. Read-only over data already in memory.

## Summary

A screen that answers three questions about the captured session without leaving the device:
what is slow, what is failing, and what is happening at the same time as what. Every figure comes
from requests `NetworkLogger` already holds, so this feature adds no capture, no storage and no
cost to the request path.

## Background

Confirmed in code on 2026-09-05:

- `NetworkLogger` is an actor holding `[HTTPRequest]` and publishing changes through an
  `AsyncStream` (`updates`). `NetworkLogsViewModel` already subscribes to it and keeps a filtered
  array in `requests`.
- Each `HTTPRequest` carries `requestDate`, `responseDate`, `requestDuration` (milliseconds, a
  `Float`), `responseCode`, `responseBodyLength`, `requestMethod`, `shortType`, `isGraphQL`,
  `graphQLOperationName`, and a `host` accessor added during the filter work.
- `NetworkLogFilter` (3.8.0) is a pure value type with a `matches(_:now:)` predicate over nine
  dimensions, and `NetworkLogsViewModel.filter(items:searchTerm:filter:)` is a static pure
  function.
- The project targets iOS 16, so **Swift Charts is available** and adds no dependency.
- `LabeledContent`, the chip components and the `MenuSectionID` conventions are all established.

## Goals

- Show summary figures for the captured session: request count, error rate, transferred bytes,
  and median and 95th percentile duration.
- Break traffic down by host and by endpoint, sorted to put the worst first.
- Show a waterfall of recent requests on a shared time axis, so overlapping and serialised calls
  are visible at a glance.
- Respect the network log's active filter and search, so the stats describe whatever subset is on
  screen.
- Keep every calculation in a pure type that can be tested without a network or a view.

## Non-Goals

- **Persisted history or trends across launches.** The log is an in-memory FIFO; stats describe
  the current session only.
- **Per-request timing phases** (DNS, TLS, first byte). `URLSessionTaskMetrics` is not collected
  today; adding it is a separate change to the capture path and would belong in its own spec.
- **Exporting stats.** The HAR export already carries the raw data; a chart is a view of it.
- **Alerting or thresholds.** Nothing watches the numbers and warns.

## Design

### Component 1: `TrafficStatistics` (new, pure)

```swift
struct TrafficStatistics: Equatable, Sendable {
    struct Summary: Equatable, Sendable {
        var requestCount: Int
        var failureCount: Int          // status >= 400, plus no-response entries
        var pendingCount: Int
        var bytesReceived: Int
        var medianDuration: Double?    // milliseconds; nil when nothing completed
        var p95Duration: Double?
        var wallClockSpan: TimeInterval?
    }

    struct HostBreakdown: Identifiable, Equatable, Sendable {
        var id: String                 // the host
        var requestCount: Int
        var failureCount: Int
        var medianDuration: Double?
        var bytesReceived: Int
    }

    struct EndpointBreakdown: Identifiable, Equatable, Sendable {
        var id: String                 // "METHOD host/path" with query stripped
        var requestCount: Int
        var medianDuration: Double?
        var slowestDuration: Double?
        var failureCount: Int
    }

    var summary: Summary
    var hosts: [HostBreakdown]         // sorted by failure count, then median duration
    var endpoints: [EndpointBreakdown] // sorted by slowest duration

    static func compute(from requests: [HTTPRequest]) -> TrafficStatistics
}
```

Percentiles use the nearest-rank method on completed requests only; pending requests are counted
separately rather than treated as zero-duration, which would flatter the numbers. Endpoint
identity strips the query string and collapses a numeric path segment to `:id`, so
`/users/1` and `/users/2` aggregate — otherwise a REST API produces one endpoint per record and
the list is useless.

### Component 2: `WaterfallSeries` (new, pure)

```swift
struct WaterfallEntry: Identifiable, Equatable, Sendable {
    var id: String
    var label: String              // GraphQL operation name, else "METHOD /path"
    var start: TimeInterval        // seconds from the series origin
    var duration: TimeInterval
    var isFailure: Bool
    var isPending: Bool
}

struct WaterfallSeries: Equatable, Sendable {
    var origin: Date
    var span: TimeInterval
    var entries: [WaterfallEntry]  // newest last

    static func build(from requests: [HTTPRequest], limit: Int = 40) -> WaterfallSeries
}
```

The series takes the most recent `limit` requests, sets the origin to the earliest of their start
times, and expresses every bar in seconds from that origin. A pending request runs to the end of
the span and is drawn open-ended.

### Component 3: The screen

`TrafficStatsView` + `TrafficStatsViewModel`, reached from a chart-icon toolbar button on
**Network Logs** rather than its own menu row — it describes the list you are looking at, and a
separate menu row would divorce it from the filter that gives it meaning.

The view model observes the same filtered array as `NetworkLogsViewModel`, so the active search
and filter chips narrow the stats. A caption under the title states what the figures cover:
"21 of 340 requests, filtered".

Sections:

1. **Summary** — a compact row of figures, not big-number hero tiles: requests, failures, median
   and p95 duration, bytes received. Tabular figures, and the failure count carries semantic
   colour only when it is non-zero.
2. **Waterfall** — a Swift Charts bar chart, one horizontal bar per request against a seconds
   axis, coloured by outcome (success, failure, pending). Tapping a bar pushes that request's
   detail page.
3. **Slowest endpoints** — the endpoint breakdown, showing median and slowest duration with a
   count.
4. **By host** — the host breakdown with request count, failure count and median duration.

Empty and near-empty states matter here: with nothing captured, the screen explains that stats
appear once requests are logged rather than showing zeroes and an empty chart.

### Component 4: Testing

- `TrafficStatisticsTests` — median and p95 for even and odd counts, single element, and no
  completed requests; failures counted for 4xx, 5xx and no-response; pending excluded from
  percentiles; endpoint identity collapses numeric segments and strips queries; host and endpoint
  sort order.
- `WaterfallSeriesTests` — origin is the earliest start, offsets and span are correct, the limit
  keeps the most recent entries, a pending request runs to the end of the span, and an empty input
  produces an empty series rather than a crash.
- `TrafficStatsViewModelTests` — the statistics recompute when the filtered array changes, and the
  caption reports the filtered and total counts.
- Strings go in a `TrafficStats.json` fragment in all twelve languages, including the plural
  "%lld of %lld requests" forms.

## Risks and mitigations

- **Recomputing on every log update.** With a live app the log changes constantly. The view model
  recomputes on a 500 ms debounce, matching the existing search debounce, and computes on a
  detached task the way filtering already does.
- **Chart labels in twelve languages.** Axis labels are numbers and a unit; the legend and section
  titles go through the catalog. Arabic reverses the chart's reading order, which Swift Charts
  handles through the environment's layout direction already set by the menu.
- **A misleading median.** With fewer than five completed requests the median is noise, so the
  summary shows the raw durations instead of percentiles below that threshold.
