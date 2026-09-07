# Waterfall: overview strip and windowed detail — Design

**Date:** 2026-09-07
**Status:** Approved
**Supersedes:** the time-scale design shipped in 4.5.0 (`WaterfallTimeScale`'s global points-per-second rule, the frozen label column, and the two-axis scroll)

## The problem

The full-page waterfall shipped in 4.4.0 and was given a real time scale in 4.5.0. On real
traffic it still does not work. From the page as shipped, with fifteen requests in the log:

- Only three or four bars are on screen at once. Rows 6 through 15 are empty, because the axis
  is zoomed so that a screen holds about two seconds while the log spans far more.
- Row labels are `GET /json`, `GET /get`, `GET /comments` — **no host**. With one host that is
  merely terse. With a dozen it is unusable, and `WaterfallEntry` has no host to show.
- Duration text runs off the right edge (`1.` for a 1.25 s request).
- Reaching request 15 means scrolling right through a great deal of nothing.

The zoom is not a bug in the 4.5.0 work; it is what that design asks for. A single absolute axis
zoomed enough to make short bars visible *must* leave most rows empty at any scroll position.
The fix is a different design, not a different constant.

## Decisions taken

Each of these was settled with the owner before this document was written. They are recorded
because they are the reason the design looks as it does, and reversing any one of them changes
the rest.

1. **The page's job is browsing all traffic with timing as context** — not reading concurrency.
   The Network Logs list already gives every request with its duration; this page adds the shape
   of traffic over time and a way into any of it.
2. **Overview strip plus windowed detail.** A compressed full-span strip drives a zoomed detail
   list below it. Chosen over a single-screen sparkline list and over keeping the scrolling axis.
3. **The detail contains only what the window contains.** Dead rows become structurally
   impossible rather than merely rarer.
4. **The Traffic Stats section becomes the same strip**, showing all traffic instead of the last
   seven bars, and tapping it opens the page at that point. This releases the constraint set when
   the page was first built — that the page must look like the summary section — by changing both
   to the same thing.
5. **Zoom is a pinch on the detail list.** Chosen over a segmented picker and over draggable
   window edges, with the costs below accepted deliberately.

## Non-goals

- Reading precise concurrency. Overlap is visible when you zoom in far enough, but the page is
  not optimised for it and does not claim to be.
- Filtering, searching or sorting. Network Logs owns those, and duplicating them here would make
  two screens that disagree.
- Grouping by host. Rows stay in time order; the host is shown per row.
- Any change to how requests are captured, or to `WaterfallSeries`' shared-axis maths.

## Architecture

`Sources/Scyther/Features/TrafficStats/`:

| File | Responsibility |
| --- | --- |
| `WaterfallWindow.swift` *(new)* | The visible slice of time as a pure value. Owns every rule about clamping, zooming and moving. No SwiftUI, no UIKit. |
| `WaterfallOverviewStrip.swift` *(new)* | The compressed full-span strip. One view used in two places, with an optional window indicator and an optional drag. |
| `WaterfallView.swift` *(rewrite)* | The page: strip, detail list, caption. |
| `WaterfallViewModel.swift` *(change)* | Owns the window; derives the rows the window contains; owns the caption. |
| `WaterfallTimeScale.swift` *(change)* | Computes the scale *within a window* rather than one scale for the whole series. |
| `WaterfallSeries.swift` *(change)* | `WaterfallEntry` gains `host` and `shortHost`. |
| `TrafficStatsView.swift` *(change)* | The Waterfall section becomes the strip. |

`WaterfallChartStyle` keeps the colours and the legend, which are unchanged and shared.

### Why a separate window value

Every rule that decides what you can see — how far you may zoom, where the window may sit, what
happens when it runs off the end of the log — is arithmetic over two numbers. Keeping it in a
value type means the pinch gesture computes nothing: it hands a magnification factor to
`zoomed(by:)` and installs the result. That is what makes the behaviour testable despite the
gesture not being, and it is the direct answer to the cost accepted in decision 5.

## The window

```swift
struct WaterfallWindow: Equatable, Sendable {
    /// Seconds from the series origin to the window's left edge.
    let start: TimeInterval
    /// How many seconds the window spans.
    let duration: TimeInterval
}
```

Constructed against a series' `span` and its shortest measured duration, which together fix the
limits:

- **Widest** — `duration == span`, `start == 0`. The whole log. You cannot zoom out past it
  because there is nothing beyond it.
- **Narrowest** — the duration at which the shortest measured request would render `24pt` wide
  *against the detail list's plot width*, which is the row's width less the label and duration
  columns. Zooming further magnifies nothing: every bar is already legible and the only thing
  that grows is the empty space between them. The plot width is passed in, so the limit is a
  function of the geometry the list actually has rather than an assumed screen size.
- **Position** — `start` is clamped to `0...(span - duration)`, so the window can never show time
  the log does not cover. Zooming re-clamps: zooming out at the right-hand end pulls the window
  left rather than off the end.

A series whose shortest and longest measured requests are the same length, or which holds one
request, has a narrowest window equal to its widest. Zoom is then a no-op and the UI disables it
rather than letting a gesture do nothing.

Pending and zero-length requests are excluded when picking the shortest duration, as they are
excluded from the scale today. A pending request has no measured length to be legible at.

### Default

**The page opens with the window at its widest — the whole span.** This was called out and
accepted: the first frame therefore looks like a plain list of every request with small bars and
the duration text carrying the meaning. Zoom is the escape, and the strip shows there is more
resolution available. Opening pre-zoomed onto recent traffic would look better on arrival and
start the developer somewhere they did not ask to be.

Opening the page from the Traffic Stats strip is the exception: the tap names a point in time,
and the page opens with a window of `span / 8` centred there, clamped to the limits above. An
eighth is wide enough to carry context around the tap and narrow enough to be worth the
navigation; picking the narrowest allowed window instead would be well defined but could land the
developer inside a tenth of a second.

## The strip

A `Canvas` — one drawing pass, not a stack of views. At five thousand captured requests a view
per request would be five thousand views; a `Canvas` draws five thousand rects and stays cheap.
This matters because both the page and Traffic Stats now build from the entire log rather than
the most recent handful.

Each request is one horizontal rect: `x` and `width` from its start and duration against the full
span, `y` from its index against the request count, height `min(3, availableHeight / count)`
with a floor of `1`. Colour is the status colour it already has. Minimum width `1pt`, so a 20 ms
request in a 60 s log is a dot rather than nothing.

Two configurations of one view:

- **On the page** — 96 pt tall, draws the window as a translucent overlay with edge rules, and
  takes a drag that moves the window's centre to the touch. Dragging is the only way to move the
  window.
- **In Traffic Stats** — 72 pt tall, no window overlay, and a tap reports the time it landed on
  so the page can open there.

## The detail list

A `List` of the entries the window contains — an entry counts as contained when its span
intersects the window's, so a request that starts before the window and finishes inside it is
shown, clipped, rather than missing.

Each row is 44 pt, matching the menu's rows, and is a `NavigationLink` to `LogDetailsView` as the
page's rows already are. Left to right:

- The short host, dimmed, then the existing label: `ipify · GET /?format=json`. **Amended** — see
  [Amendments](#amendments): shipped as the host stacked above the path instead.
- The bar, positioned within the window, minimum width `3pt`, clipped at the window's edges. A
  request continuing past an edge is drawn flush to it, so the clipping reads as continuation
  rather than as a short request.
- The duration, right-aligned, tabular figures, `—` when pending.

Colour means status and only status. The host is identified by its text, not by a second colour
scale — a per-host hue alongside four status colours makes twelve hosts noisy and makes a failure
harder to spot, which is the one thing the colour must do.

### Short host

`shortHost` is derived once, when the entry is built:

1. Drop a leading `www.`.
2. Split on `.`. If the first label is one of `api`, `www`, `cdn`, `static`, `assets`, `app`,
   `m` and there are three or more labels, use the second label. Otherwise use the first.

So `api.ipify.org` → `ipify`, `httpbin.org` → `httpbin`,
`jsonplaceholder.typicode.com` → `jsonplaceholder`, `cdn.assets.example.com` → `assets`
(**amended** — see [Amendments](#amendments): shipped as `example`). A host that is an IP
address, or has no dots, is used as-is. The full host stays on the entry for the log detail page
to show.

## Zoom

`MagnificationGesture` — not `MagnifyGesture`, which is iOS 17 and the package floor is iOS 16 —
attached to the detail list and combined with `.simultaneously(with:)` so it does not take the
list's vertical scrolling away from it. **Amended** — see [Amendments](#amendments): shipped
attached with `.gesture(_, including:)` instead. The gesture's magnitude goes to
`WaterfallWindow.zoomed(by:)`, which clamps; the view installs whatever comes back.

Zooming keeps the window's centre fixed, so pinching does not slide the developer through time
while they are trying to change resolution.

**VoiceOver and Switch Control** reach the same range through `.accessibilityAdjustableAction` on
the strip, halving or doubling the window's duration per step within the same clamps. A zoom
available only to a pinch would be a control those users cannot operate, which is not something
this toolkit gets to ship a month after adding an accessibility audit.

## Traffic Stats

The Waterfall section keeps its header and its **See all** link and replaces its bars with the
strip, built from the whole log rather than `WaterfallSeries.defaultLimit`. Its footer states the
span, the request count and the host count.

`defaultLimit` is `build(from:limit:now:)`'s default argument, not a lone constant, and two tests
pin it — including one asserting that "a preview has to read as one", which is precisely the
policy this design reverses. Implementation decides whether the parameter keeps a default at all;
what is settled here is that neither view passes seven any more, and that the test encoding the
old policy is rewritten rather than deleted quietly.

## What is removed

Named because it shipped hours before this document and its removal should be visible in review,
not discovered:

- The frozen label column and its counter-offset layout pass.
- The two-axis `ScrollView` and the ruler pinned inside it as a sticky header.
- `WaterfallTimeScale`'s global points-per-second rule — the median-at-24 pt scale, the tail
  floor, and the 50,000 pt ceiling. The median-and-tail measurements survive; what goes is
  choosing one scale for the whole series. **Amended** — see [Amendments](#amendments): the
  median and tail measurements did not survive after all; only the zoom limit's shortest-measured
  reading did.

The preview waterfall's own drawing survives inside `WaterfallChartStyle` for the legend and
colours.

## Edge cases

| Case | Behaviour |
| --- | --- |
| Empty log | The existing `ContentUnavailableView`. No strip, no list. |
| One request | Window is the request's own span; zoom disabled; strip drawn with a single bar. |
| All requests the same length | Narrowest window equals widest; zoom disabled. |
| Window over a gap in traffic | A single row saying nothing is in this window, rather than a blank list. |
| Pending request | Drawn to the window's right edge in the pending colour, duration `—`. |
| Request longer than the window | Drawn flush to both edges. |

## Localisation

Every new string goes through `localized(_:)`, added to
`Scripts/localization/strings/TrafficStats.json` in all twelve languages, with the catalogue
rebuilt. Spans, counts, durations and host names are formatted, not translated; any sentence
embedding one is a single key with an interpolation.

## Testing

**Pure, so tested directly:**

- `WaterfallWindow` — clamping at both limits, that zooming holds the centre, that zooming out at
  the end pulls the window back rather than past the span, that a degenerate series disables
  zoom, and `contains(_:)` for an entry starting before and ending inside the window.
- `shortHost` — the seven examples above plus an IP address and a single-label host.
- Strip geometry as a pure function of span, count and size: bar rects, the height floor, and the
  minimum width.
- `WaterfallViewModel` — the rows a window yields, the caption, the empty-window state, and that
  opening from a tapped time centres the window there.

**Not unit-tested, and said plainly:** the pinch gesture itself, and its interaction with the
list's scrolling. Both are verified by hand on the simulator. This is the accepted cost of
choosing a gesture over a control, and the reason the arithmetic behind it was pulled into a
value type.

## Verification on device

Before the work is called done, on the simulator, with the example app's traffic:

1. Open the page and confirm it arrives showing the whole span with every row carrying a bar.
2. Pinch in and confirm the detail zooms, the strip's window narrows to match, and rows leave the
   list as they leave the window.
3. Drag the strip from one end to the other and confirm the detail keeps up and never empties
   except over a genuine gap.
4. Confirm the zoom stops at both limits rather than continuing to scale.
5. Tap a row and confirm it opens that request's log detail.
6. Open the page from the Traffic Stats strip and confirm it arrives centred on the tapped point.
7. With VoiceOver on, confirm the strip's adjustable action zooms.

## Amendments

Recorded here, against the sections above, rather than silently edited into them: each is a
deliberate, reviewed drift between this document and what shipped, kept so the next reader trusts
the spec instead of being misled by it.

- **`shortHost`'s worked example.** `cdn.assets.example.com` yields `example`, not `assets`. The
  rule as written — "unless *that* label also names infrastructure" — already says the skip
  repeats past a second generic label; `cdn.assets.example.com` is exactly that case (`cdn`, then
  `assets`, both generic, three labels still ahead), and the implementation and its tests were
  built from the rule, not from this worked example. The example was wrong the day it was
  written; the rule it illustrates was not.
- **The detail row's layout.** The host is stacked above the path, not set beside it as
  `ipify · GET /?format=json` reads. Tried side by side first, exactly as specced; it read worse
  than not showing the host at all, because a host capped to a fixed width truncated to a
  different length on every row and the paths beneath them stopped starting at a common x. See
  `WaterfallDetailRow`'s own documentation in `WaterfallView.swift` for the full account. The
  spec's own goals — the host identifying, the path still scannable — are what the amendment
  serves; the layout named to reach them was not load-bearing.
- **The zoom gesture's attachment.** `.gesture(_, including:)`, not
  `.simultaneously(with:)`. The two solve the same problem stated here — a pinch and the list's
  own scroll must not compete for the same fingers — but `.gesture(_, including:)` additionally
  lets the pinch itself be switched off, via `including: .subviews`, once
  `WaterfallWindow.canZoom` is `false`, so a request the window cannot narrow any further loses
  the gesture without also losing the list's scroll. `.simultaneously(with:)` has no equivalent
  toggle. See ``WaterfallView/magnification`` and ``WaterfallView/detail`` for where this is done.
- **The median and tail measurements.** "What is removed" above says they survive the
  `WaterfallTimeScale` → `WaterfallDurations` rename; they did not, and a later commit kept them
  regardless on the mistaken belief that the caption and the zoom limit still needed them. Neither
  does: `WaterfallViewModel.windowCaption` is built from counts alone, and the zoom limit is built
  from the shortest measured duration, not the median or the tail. Both fields, and the
  nearest-rank `percentile(_:of:)` function that computed them, were removed in the final fix wave
  this document's own review produced — see `WaterfallDurations`' type documentation for the full
  account.
