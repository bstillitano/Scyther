# Request Replay and Editor

**Date:** 2026-09-05
**Status:** Approved design — ready for implementation planning
**Part:** 3 of 5 in the networking backlog
**Depends on:** nothing. Independent of the rules engine and of breakpoints.

## Summary

From a captured request's detail page, open an editor pre-filled with that request, change what
you like, and send it again. The new response is captured by the existing interceptor and lands
in the log linked to the request it came from, so the two can be compared side by side.

This is the cheapest way to answer "does it still fail if I drop that header", without leaving the
device for a terminal.

## Background

Confirmed in code on 2026-09-05:

- `HTTPRequest` holds everything a replay needs: `requestURL`, `requestMethod`, `requestHeaders`,
  and a body on disk reachable through `getRequestBodyFilepath()` / `readRawData(_:)`.
  `requestCurl` proves the reconstruction is already possible — `URLRequest.curlString` builds a
  complete command from the same fields.
- `HTTPInterceptorURLProtocol.canServeRequest(_:)` intercepts any `http(s)` request that is not
  marked with the `Scyther_Internal_Network_Request` property. A replay fired through a plain
  `URLSession` is therefore captured and logged automatically — no new capture path is needed.
- `URLProtocol.setProperty(_:forKey:in:)` on an `NSMutableURLRequest` survives into
  `canInit`/`startLoading`, which is how the internal-request marker already works. The same
  mechanism can carry a replay's provenance.
- `LogDetailsView` already offers navigation rows and a `ShareLink`, and `TextEntryView` is an
  existing editor component with save and share.

## Goals

- Open an editor pre-filled from any captured request, in one tap from its detail page.
- Edit method, URL, headers and body, and send.
- Have the replay captured by the normal interceptor so it appears in the log with no special
  handling.
- Show, on both rows, that they are related, and let the developer jump between them.
- Compare the original and the replay on status, duration and size without leaving the app.

## Non-Goals

- **A general HTTP client.** Requests start from something already captured. There is no "new
  blank request" entry point; that is a different product.
- **Body diffing.** Comparing two JSON bodies structurally is a feature in its own right. The
  comparison covers status, duration, size and headers; bodies are opened side by side in the
  existing viewer instead.
- **Replaying a mocked response.** A request stubbed by a rule has no real response to replay
  against; the replay row is hidden for stubbed entries.
- **Editing a request while it is in flight.** That is a breakpoint (spec 2).
- **Saving replays as reusable requests.** A replay is a one-shot. Turning one into a mock is
  already covered by "Save as mock" in spec 1.

## Design

### Component 1: `ReplayableRequest` (new, pure)

A value type that converts between a captured model and a live request, with no view involvement:

```swift
struct ReplayableRequest: Equatable, Sendable {
    var method: String
    var url: String
    var headers: [(name: String, value: String)]   // ordered, editable, duplicates allowed
    var body: Data?

    /// Builds a draft from a captured request, reading its body from disk.
    init(capturing request: HTTPRequest)
    /// Builds the outgoing request, or nil if the URL is not valid.
    func makeURLRequest(replayOf originalID: String) -> URLRequest?
    /// Whether anything differs from the request this was built from.
    func isModified(from original: ReplayableRequest) -> Bool
}
```

`makeURLRequest` stamps `URLProtocol.setProperty(originalID, forKey: replayOfKey, in:)` so the
interceptor can record provenance. Header order is preserved because a duplicated header
(`Set-Cookie`, `Accept`) is meaningful and a dictionary would silently collapse it.

### Component 2: Capture-side changes

`HTTPRequest` gains one field:

```swift
/// The `randomHash` of the request this one replays, if it is a replay.
var replayOfID: String?
```

`HTTPInterceptorURLProtocol.startLoading()` reads `URLProtocol.property(forKey: replayOfKey, in:)`
and assigns it to the model before saving. That is the entire interceptor change: three lines, no
behaviour change for anything that is not a replay.

`HTTPRequestView` shows a **REPLAY** lozenge on a replayed row, in the same treatment as the
GraphQL badges.

### Component 3: The editor

`ReplayEditorView` + `ReplayEditorViewModel`, presented as a sheet from `LogDetailsView`:

- **Method** — a menu of the common verbs plus a free-text field for anything else.
- **URL** — a single-line field, validated live; Send is disabled while the URL will not parse.
- **Headers** — a list of name/value rows, each editable and swipe-deletable, with an add row.
  Rows are pre-filled from the capture. Headers `URLSession` sets itself (`Content-Length`,
  `Host`) are shown greyed and marked as managed, because editing them has no effect.
- **Body** — a row that opens `TextEntryView`, showing a byte count when present. Bodies that are
  not valid UTF-8 are shown as read-only with a note, and are sent unchanged.
- **Send** — fires the request through a plain `URLSession.shared` data task, dismisses, and
  scrolls the log to the new entry when it arrives.

Nothing about sending is special: the request goes out like any app request and comes back through
the interceptor.

### Component 4: Comparison

`LogDetailsView` gains a **Replays** section on an original that has replays, listing each with
its status, duration delta and size delta, and a link to its detail page. A replay's own detail
page gains an **Original** row linking the other way.

The deltas are computed by a pure `ReplayComparison` type — status changed or not, duration
difference in milliseconds, body size difference in bytes — so the arithmetic is unit-testable
without a network.

### Component 5: Testing

- `ReplayableRequestTests` — a draft built from a captured model preserves method, URL, ordered
  headers including duplicates, and the on-disk body; `makeURLRequest` returns nil for an invalid
  URL and stamps the provenance property otherwise; `isModified` is false for an untouched draft
  and true for each edited facet.
- `ReplayComparisonTests` — status, duration and size deltas including the equal case and the
  missing-response case.
- `ReplayInterceptorTests` — a request carrying the provenance property is logged with
  `replayOfID` set; one without it is not.
- `ReplayEditorViewModelTests` — Send is disabled for an invalid URL, header add and delete,
  managed headers are not editable.
- Strings go in the `NetworkLogger.json` fragment, which already owns the detail page's copy.

## Risks and mitigations

- **A replay that mutates server state.** Resending a `POST` can double-charge, double-post or
  double-send. The editor shows a warning line for any non-idempotent method, and Send on those
  methods asks for confirmation with an alert naming the method.
- **Provenance surviving where it should not.** The replay property is stamped per request and
  never copied onto redirects, matching how the internal-request marker is stripped in
  `willPerformHTTPRedirection`.
- **Authentication that has since expired.** A replayed request carries the original's headers,
  including a stale token. The comparison surfacing a 401 next to the original's 200 is the
  intended signal, not a bug.
