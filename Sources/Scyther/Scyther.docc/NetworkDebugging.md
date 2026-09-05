# Network Debugging

Inspect HTTP requests and responses to debug API interactions.

@Metadata {
    @PageColor(green)
}

## Overview

Scyther automatically intercepts all HTTP requests made through `URLSession` and logs them for inspection. This helps you debug API issues, verify request formatting, and understand network timing.

## Automatic Logging

Once Scyther is started, network logging is enabled automatically. All requests show up in the **Network Logs** section of the Scyther menu.

Each logged request includes:
- URL and HTTP method
- Request headers
- Request body (formatted for JSON)
- Response status code
- Response headers
- Response body
- Timing information
- cURL command for reproduction

## Viewing Requests

Open the Scyther menu and navigate to **Network Logs** to see all captured requests. Tap any request to see its full details.

### Request Details

The detail view shows:
- **Overview**: Method, URL, status code, duration
- **Request**: Headers and body sent to the server
- **Response**: Headers and body received from the server
- **cURL**: A ready-to-use cURL command to reproduce the request
- **Replays**: Every replay of this request currently in the log, and the deltas between them

## Accessing Network Data Programmatically

### Device IP Address

Get the device's public IP address:

```swift
let ip = await Scyther.network.ipAddress
print("Device IP: \(ip)")
```

### Streaming Requests

The ``NetworkLogger`` uses `AsyncStream` for real-time request updates:

```swift
// In your debug view
for await request in NetworkLogger.shared.requests {
    print("New request: \(request.url)")
}
```

## Filtering Requests

The Network Logs screen offers two ways to narrow the list, and they combine.

**Search** matches the URL, GraphQL operation name, status code, or HTTP method.

**Filter chips** sit above the list. Tap a chip to open a sheet with a multi-select checklist:

- **Method**: the HTTP methods present in the captured requests
- **Status**: 2xx success, 3xx redirect, 4xx client error, 5xx server error, or pending / no response
- **Host**: the request hosts present in the captured requests. An Include / Exclude segmented
  control in the list header decides whether the selected hosts are the only ones shown or the
  ones hidden
- **Type**: JSON, XML, HTML, Image, or Other, based on the detected response content type
- **API**: REST or GraphQL
- **GraphQL**: Query, Mutation, Subscription, or Batch / Unknown for GraphQL requests with no
  single operation type. REST requests never match a GraphQL selection
- **Duration**: under 100ms, 100ms to 500ms, 500ms to 1s, 1s to 3s, or over 3s. Requests still
  awaiting a response have no duration and never match a duration selection
- **Code**: the exact response status codes present in the captured requests
- **Recency**: last minute, 5 minutes, 15 minutes, or hour, measured from when the filter runs.
  Single-select, since each window contains the shorter ones

The icon-only chip at the start of the row opens a full-height Filters sheet that lists every
dimension, grouped into Request, Response, and Timing, with a summary of its selection. Tapping a row pushes that dimension's checklist, with
a Reset for that dimension alone; the root Filters screen offers Reset for everything.

Selections apply immediately behind the sheet. Chips combine with AND, values within a chip with
OR (Recency allows one value). Active chips are fully tinted and show the selected value when exactly one is chosen, or the
dimension name with a count when several are. A Reset button appears in each
sheet while it has a selection, and a red Clear chip appears in the bar whenever any filter is active.
Filters are held in memory for the current session only.

## Traffic Stats

The chart button in the Network Logs navigation bar opens **Traffic Stats**, which answers what is
slow, what is failing, and what was happening at the same time as what — computed from the
requests already in memory, so it adds nothing to the request path.

The screen describes the list you were looking at: search and filter chips narrow the requests
before the figures are computed, and the caption under the title says whether it is covering the
whole session (`8 requests`) or a slice of it (`21 of 340 requests`).

The summary reports the request count, how many were stubbed, failures and the failure rate,
pending requests, median and 95th percentile duration, bytes received, and the wall-clock span of
the session.

- **A stubbed response is counted but never measured.** A response a request override synthesised
  never left the device, so its duration measures Scyther rather than the server and its status
  code was authored rather than returned. Stubs are counted in *Requests* and *Stubbed* and left
  out of every duration, failure and byte total, and out of the host and endpoint breakdowns.
- **Percentiles use the nearest rank**, so every duration reported is one a request actually took
  rather than a number interpolated between two of them.
- **Below five completed requests there are no percentiles.** A median of three samples is noise,
  so the summary shows the fastest and slowest round trips instead.
- **A request that never came back is counted as pending and as a failure**, never as a
  zero-duration completion, which would flatter every latency figure.

The **waterfall** draws the most recent forty requests as bars on a shared seconds axis, labelled
with their durations and coloured by outcome. Bars that overlap were in flight at the same time; a
staircase means the calls were serialised. A pending request runs to the end of the axis, because
its real end is not yet known.

**Slowest Endpoints** groups by `METHOD host/path`, dropping the query string and collapsing any
numeric or UUID path segment to `:id`, so `/users/1` and `/users/2` aggregate. **By Host** puts the
worst offender first: most failures, then slowest median.

Stats describe the current session only — the log is an in-memory FIFO, so nothing persists across
launches.

## Exporting the Whole Log

The export button in the Network Logs navigation bar packages the requests currently shown into
`<App-Name>-Network-Log-<timestamp>.zip`, named after the host app. Search and filter chips narrow what is included.

The archive contains:

- `network-log.har`, a HAR 1.2 document readable by Charles, Proxyman, Chrome DevTools, and most
  HTTP tooling. Image bodies are embedded as base64.
- `requests/<index>-<METHOD>-<host>/` per request, holding `request.curl` and the raw request
  and response bodies when they exist.

The export sheet shows progress while the zip is built. A **Redaction** toggle, on by default,
replaces values whose header name, query parameter, JSON key, or form field looks sensitive
(authorization, tokens, cookies, passwords, API keys, sessions) with `REDACTED`, and scrubs
`Bearer` credentials and JWT-shaped strings wherever they appear. Redacted HAR files carry a
`log.comment` saying so. This is an attempt, not a guarantee: secrets under unusual names or in
formats the patterns do not cover pass through untouched.

Because the archive can include full headers, cookies, authentication tokens, and bodies, tapping
**Export** shows a sensitivity alert first; confirming opens the system share sheet. The file is
deleted when the sheet closes.

## Request Overrides

Logging shows what the app asked for and what came back. **Request Overrides** changes it:
reached from **Networking → Request Overrides**, it mocks endpoints, serves local files, rewrites
headers and degrades the connection, all without touching the app's networking code. The API type
is still called ``NetworkRule``, so an override in the UI is a rule in code.

Every override matches on HTTP method, host, path and query — an omitted facet places no
constraint, and host and path accept `*` as a wildcard. Overrides are evaluated top to bottom:

- The **first** matching mock or map local wins and short-circuits the network.
- The **first** matching condition supplies the latency, bandwidth ceiling and failure rate;
  they are not stacked from several overrides.
- **Every** matching header rewrite applies, and the **last** override to name a header decides
  what happens to it: a later `set` beats an earlier `remove` just as it beats an earlier `set`,
  and a later `remove` beats an earlier `set`. Header names are compared case-insensitively, so
  `Authorization` and `authorization` are one header. Within a single rewrite there is no order to
  appeal to, so `set` is applied before `remove` and a header named in both ends up removed.

Reordering the list is what changes precedence.

### What matching compares

- Method, host and path are compared **case-insensitively**. Query names are compared
  **case-sensitively**, because a query name is data rather than protocol.
- The path is compared **percent-encoded**, exactly as it travels on the wire. `%2F` is therefore
  not a separator — `/v1/a%2Fb` is one segment and does not satisfy a rule for `/v1/a/b` — and a
  path copied out of the log, out of a HAR, or off an address bar matches the request it came
  from. A path typed with a literal space will not.
- A **trailing slash is part of the path**: `/v1/users` and `/v1/users/` are different paths. Use
  `/v1/users*` to match both. A URL with no path at all, `https://api.example.com`, is matched as
  `/`.
- Every query pair listed must be present. A key that repeats is satisfied by **any** of its
  occurrences, so `page=2` matches `?page=1&page=2`, and a key present with no value — `?flag` —
  reads as an empty value. Values are compared percent-decoded.
- A pattern left **blank** places no constraint at all, exactly as leaving the facet out does. So
  does one that matches everything anyway — a path of `*` set to Wildcard, or `/` set to Contains
  — which is why the editor refuses to save either spelling. The engine still honours them for a
  rule built in code; the guard is on what the editor will save.

### The four actions

| Action | Type | What it does |
| --- | --- | --- |
| Mock Response | ``MockResponse`` | Answers with a status code, headers and a body typed into the editor, after an optional delay. |
| Map Local File | ``MapLocalFile`` | Answers with the contents of a file on the device, with a status code and `Content-Type`. |
| Rewrite Headers | ``NetworkHeaderRewrite`` | Sets and removes headers on the outgoing request, then lets it go to the network. |
| Network Condition | ``NetworkCondition`` | Adds latency, caps bandwidth, and fails a fraction of matching requests with a `URLError`. |

- Note: A condition's latency and a mock's delay are each capped at 30 seconds. Neither is waited
  out on the thread the request started on, so a delayed override cannot hold up traffic it does
  not match.
- Note: ``MockResponse/headers`` is a dictionary, so a mocked response cannot repeat a header
  name. Where a real response may send `Set-Cookie` more than once, only one value survives, and a
  HAR import keeps the last of the repeats.
- Note: ``MapLocalFile/relativePath`` holds an **absolute** path despite its name. A container
  path is not something anyone can type on a device, so it has to come from code or be copied from
  Scyther's file browser. A path that cannot be read fails safely — the request goes to the real
  network.

### Saving a captured request as a mock

The request details page carries a **Save as mock** button whenever the response came off the
wire. It opens the override editor pre-filled from the capture: matching that request's method,
host and path exactly, answering with its status code, its headers and its body. The query string
is left unconstrained, because the page number that happened to be captured is rarely what the
mock is about, and headers describing the wire encoding (`Content-Encoding`, `Content-Length`,
`Transfer-Encoding`) are dropped, because the stored body is the one `URLSession` already decoded.

The override arrives **disabled**. Nothing about the app's behaviour changes until it is switched
on, from the editor or with a swipe on the list.

A response an override synthesised cannot itself be saved as a mock — there would be nothing to
learn from the copy. Those rows are marked instead: the log list shows a pink **MOCKED** badge,
and the details page lists every override that shaped the request in an **Overrides** row of the
Developer Info section.

### Importing a HAR file

**Import from HAR** in the list's add menu reads a HAR 1.2 document — one exported by Scyther, or
captured in Charles, Proxyman or Chrome DevTools — and turns each entry into a mock override named
`<METHOD> <path>`, matching that method, host and path. Entries are read one at a time, so a
capture full of the things a real HAR contains — an aborted request with no `response` object, a
multipart upload whose `postData` carries `params` and no `text`, an entry whose URL cannot be
parsed — costs those entries and nothing else. The alert reports both numbers: how many overrides
were added, and how many entries produced none.

A response body labelled `encoding: "base64"` is decoded even when it is wrapped across lines, as
Charles and other MIME-style encoders write it, and text that plainly is not base64 is taken as
the literal body it is rather than decoded into bytes that came from nowhere.

Every imported override arrives disabled, for the same reason a saved mock does: importing a
colleague's capture should never silently change what the app does.

### The master switch

**Enable Request Overrides**, at the top of the list, suspends every override at once without
deleting any of them. It is the fastest way to check whether a behaviour is the app's or an
override's. It is persisted, so it survives relaunch.

### Registering overrides from code

``Scyther/Network/rules`` is the programmatic entry point. It is `@MainActor`, like every other
Scyther singleton, and every member of it is inert until ``Scyther/start()`` has run — which it
does not do on an App Store build. The code below can sit unguarded in `didFinishLaunching`: on a
release build it reads back nothing, writes nothing to preferences, and puts no file in the user's
container.

```swift
// Persisted: written to UserDefaults, listed in the menu, survives relaunch. The
// identifier is a constant, so relaunching updates this override rather than adding
// a second copy of it.
let emptyCart = UUID(uuidString: "6F0B0C3E-4C1E-4E3D-9C0B-0F5E7A9D2B41")!
Scyther.network.rules.add(
    .mock(id: emptyCart,
          name: "Empty cart",
          matching: .path("/api/cart"),
          returning: .json(#"{"items": []}"#))
)

// This launch only: never written to disk, listed read-only under "Registered in Code".
Scyther.network.rules.addTransient(
    .headers(name: "Staging auth",
             matching: .host("*.staging.example.com"),
             set: ["Authorization": "Bearer test-token"])
)

// Suspend everything without deleting anything.
Scyther.network.rules.isEnabled = false
```

- Important: ``NetworkRules/add(_:)`` **persists** the override and shows it in the menu, where a
  developer can edit or delete it. ``NetworkRules/addTransient(_:)`` does not: transient overrides
  live for the launch that registered them, are shown read-only, and cannot be reordered. Use the
  transient form for anything the app registers for itself, so it cannot outlive the run that
  created it.
- Important: Both are an upsert on ``NetworkRule/id``: an override whose identifier is already
  known replaces that override in place, and whatever body file it owned is reclaimed unless
  another override still points at it. Code that runs on every launch should pass a constant
  `id`, as the example above does. An override built without one gets a fresh identifier every
  time, so the same call in `didFinishLaunching` would store another copy of it on every launch.
- Important: An identifier lives in exactly one of the two lists. Registering a transient override
  under an identifier ``NetworkRules/add(_:)`` stored moves it across, and vice versa: the last
  registration wins outright.
- Note: ``MockResponse/json(_:status:delay:)`` writes nothing when it is built. Its bytes travel
  with the value and are written when the override holding it is stored, so a response that is
  never registered leaves nothing on disk. Both `add` methods return `false` when nothing was
  stored — Scyther is not running, or those bytes could not be written — rather than storing an
  override that would answer with the right status code and an empty body.

Transient overrides are evaluated after every persisted one, so a persisted mock on the same
endpoint takes precedence.

### Stubbing a UI test

Transient overrides make a UI test hermetic without a stub server:

```swift
// In the app, behind a launch argument the test sets.
if ProcessInfo.processInfo.arguments.contains("-UITestStubs") {
    Scyther.network.rules.isEnabled = true
    Scyther.network.rules.addTransient(
        .mock(name: "Profile",
              matching: .host("api.example.com", path: "/v1/profile", methods: ["GET"]),
              returning: .json(#"{"name": "Ada"}"#))
    )
    Scyther.network.rules.addTransient(
        .condition(name: "Slow uploads",
                   matching: .path("/v1/upload", methods: ["POST"]),
                   NetworkCondition(latency: 2, failureRate: 0.5))
    )
}
```

```swift
// In the test.
let app = XCUIApplication()
app.launchArguments += ["-UITestStubs"]
app.launch()
```

Because they are transient, the next launch starts clean — a stub left enabled by a failed run
cannot quietly break the next one.

- Note: Overrides only apply to traffic Scyther intercepts, which is `URLSession` traffic through
  a standard configuration. A custom `URLSessionConfiguration` that does not carry Scyther's
  `URLProtocol` bypasses overrides exactly as it bypasses logging.

## Request Replay

The request details page carries a **Replay this request** button. It opens an editor pre-filled
from the capture and sends whatever is left there when the confirm button is tapped.

### The editor

- **Method** — a picker of the common verbs, plus **Other** for anything else.
- **URL** — validated live; the confirm button stays disabled while it will not parse into an
  absolute HTTP URL.
- **Headers** — one editable row per captured header, swipe-deletable, with an add row. Headers
  `URLSession` owns (`Content-Length`, `Host`, `Connection`) are shown but disabled and are
  dropped rather than sent. A duplicated header name travels as the comma-joined field HTTP
  defines rather than one row winning.
- **Body** — opens the same text editor the rest of the toolkit uses. A body that is not valid
  UTF-8 is marked as such and sent unchanged; the logger only writes UTF-8 request bodies to
  disk, so a binary body cannot be recovered from the capture at all.

### What sending does

Nothing about a replay is special-cased. It goes out on an ordinary `URLSession` and comes back
through the same interceptor as traffic the app makes, which means:

- **it is logged as its own entry**, marked with a teal `REPLAY` badge, so a resent request can
  never be mistaken for one the app made; and
- **enabled overrides apply to it**, so replaying a request a mock matches serves the mock, with
  both badges on the row. The editor states this in a footer.

A response an override synthesised offers no replay button — the override would only synthesise
it again.

Any method outside `GET`, `HEAD` and `OPTIONS` warns in the editor and asks for confirmation in
an alert naming the method, because resending it can repeat whatever it changed.

### Comparing a replay to its original

Each replay records which capture it was built from. The original's page
lists its replays with each one's method, status and the signed duration and size deltas — replay
minus original — and each row links to that replay. The replay's own page links back through a
**Replayed from** row, or says the original is no longer in the log once it has been cleared.

Both sections follow the log as it changes, so a replay landing after the editor dismissed
appears without leaving the page.

- Note: Provenance is stamped per request and stripped from redirects, so the entry a redirect
  produces is a request in its own right rather than a second replay of the same original.

## Exporting cURL Commands

Every request can be exported as a cURL command from the request details page. Tap the
share button in the top-trailing corner of the navigation bar, or the "Export cURL request"
row in the Developer Info section; both present the same system share sheet. This is useful for:
- Sharing with backend developers
- Testing in terminal
- Creating API documentation
- Debugging in tools like Postman

Example exported cURL:

```bash
curl -X POST 'https://api.example.com/users' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer token123' \
  -d '{"name": "John", "email": "john@example.com"}'
```

## Best Practices

### 1. Sensitive Data

Be aware that network logs may contain sensitive data like:
- Authentication tokens
- Personal information
- API keys

Scyther is automatically disabled in App Store builds to prevent exposure.

### 2. Large Responses

Very large response bodies are truncated for performance. If you need to inspect a large response, use the cURL export to replay the request.

### 3. Binary Data

Binary responses (images, files) are noted but not displayed inline. Use the cURL command to download them separately.

## Troubleshooting

### Requests Not Appearing

If requests aren't being logged:

1. Ensure `Scyther.start()` was called before making requests
2. Check that you're using `URLSession` (not custom networking)
3. Verify the app isn't an App Store build

### Custom URLSession Configurations

If you're using a custom `URLSessionConfiguration`, Scyther's protocol may not be automatically registered. Ensure you're using standard session configurations.

## See Also

- ``TrafficStatistics``
- ``WaterfallSeries``
- ``NetworkLogger``
- ``NetworkLoggerRequest``
- ``Network``
- ``NetworkRules``
- ``NetworkRule``

