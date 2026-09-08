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
   to the same thing. *Reversed after the owner judged it unusable at real request counts — see
   Amendments, "The Traffic Stats strip, zoomed instead of whole".*
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

**Revised twice after device verification — see [Amendments](#amendments).** What shipped first,
and what this section originally argued for, was the whole span. What shipped second was the
window anchored on the most recent traffic and sized so a typical request was legible. What ships
now is the same anchoring with a flat half the span. All three are recorded below, in the order
they happened, because neither of the first two was a wrong guess corrected in review — each was
deliberately decided, built, and only reversed once it was driven against real use, and that
history is worth keeping precisely because the reasoning behind each one still reads as sound in
isolation.

**What was decided and shipped first: the page opens with the window at its widest — the whole
span.** This was called out and accepted: the first frame therefore looks like a plain list of
every request with small bars and the duration text carrying the meaning. Zoom is the escape, and
the strip shows there is more resolution available. Opening pre-zoomed onto recent traffic would
look better on arrival and start the developer somewhere they did not ask to be.

**Why it failed on real traffic.** The owner ran the page against a log spanning 3,522 seconds —
an hour, with two short bursts of traffic an hour apart — and reported three symptoms that are all
the same cause: the pinch appeared to do nothing, no window highlight ever appeared, and every bar
in the detail list was an identical 3pt tick. The last one is the whole-span default failing on
its own terms. At that span a 43ms request and a 1.06s request both render at the detail list's
3pt floor — the window was wide enough that neither could be told apart by width, which is the one
thing the plot column exists to show. "Opens honest, zoom is the escape" was the design's own
phrase for this default, and it assumed the reader would zoom past that immediately; against an
hour-long log the first frame did not read as an honest starting point to zoom from, it read as
broken, because nothing on it looked different from anything else on it. `marksASubset` being
`false` at the whole span compounded it — see [Verification on device](#verification-on-device)
check 1, and its own type documentation on `WaterfallWindow` — so there was also no overlay on the
strip to suggest that narrowing the window was even an available move, on the one screen state
where a reader most needed that hint.

**What shipped second: anchored on the newest traffic, sized so the *median* measured request
rendered at `WaterfallWindow.targetShortestBarWidth`** (the same "24pt is legible" figure the zoom
floor already uses for the *shortest* request), clamped into the window's own narrowest-and-widest
limits. When the demanded width already reached or exceeded the whole span — every short log, and
the only case the original default was ever actually tested against by hand — the clamp pinned the
window to the whole span and nothing changed: a strict narrowing of the whole-span rule, not a
replacement of it in the one case that made it safe to begin with.

**Why it, in turn, opened too tight.** The median rule fixed the hour-long capture — the strip's
overlay was visible from the first frame on any log that needed it — but sizing the window to make
exactly one median-legible request visible also meant the window could be very narrow on an
ordinary log with nothing wrong with it: a 19-request session opened showing `1 of 19`. Legible and
*comfortable to open on* turned out to be two different targets. The owner asked directly for the
second one: a page that opens on roughly half its traffic, not on however few requests happen to be
legible.

**The rule now: a flat half the series' span**, still anchored at the end of the series, still
clamped into the window's own narrowest-and-widest limits exactly as both earlier rules were. No
single request's duration enters the arithmetic at all any more — the median that the second rule
needed for its own "typical request" figure has no remaining caller and was removed alongside this
change. A log whose narrowest limit already sits above half its span opens at that limit instead of
at the plain half; a log too short to zoom at all — where the narrowest limit already equals the
whole span — still opens at the whole span, the same degenerate case both earlier rules also
produced there, for the same underlying reason. The function is `WaterfallWindow.opening(span:narrowest:)`,
and it carries the full account of all three rules, in order, in its own documentation.

Two consequences of anchoring rather than staying at the whole span: the window is now usually a
subset of the log the instant the page opens, so the strip's overlay draws immediately on any log
long enough to need it — direct evidence there is more to see, which the whole-span default could
never show on its own first frame. And the caption under the detail list, built from
`visibleRows.count` and `layout.count` regardless of what fraction of the span the window
currently covers, reads correctly whether that window is the whole log or a narrow slice of it —
it never assumed a whole-span open in the first place.

Opening the page from the Traffic Stats strip is still the exception described in the original
design: the tap names a point in time, and the page opens with a window of `span / 8` centred
there, clamped to the limits above, in place of the newest-traffic default. An eighth is wide
enough to carry context around the tap and narrow enough to be worth the navigation; picking the
narrowest allowed window instead would be well defined but could land the developer inside a tenth
of a second.

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

*Amended after the whole-log strip described below shipped and was judged unusable at real
request counts — see [Amendments](#amendments), "The Traffic Stats strip, zoomed instead of
whole". The section it describes is what shipped first, not what is on the branch now; read that
amendment for the current design.*

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
- `WaterfallWindow.opening(span:narrowest:)` — a log whose narrowest limit sits above half its
  span opens at that limit rather than at the plain half, an ordinary log opens at half its span
  anchored on the newest traffic, a log too short to zoom at all (where the narrowest limit
  already equals the span, whether from a single measurement or nothing measured) falls back to
  the whole span, and an empty series produces the same degenerate, non-dividing window every
  other empty-series case on the type does.
- `shortHost` — the seven examples above plus an IP address and a single-label host.
- Strip geometry as a pure function of span, count and size: bar rects, the height floor, and the
  minimum width.
- `WaterfallViewModel` — the rows a window yields, the caption (including against a window that
  opens as a genuine subset, not only the whole span), the empty-window state, and that opening
  from a tapped time centres the window there.
- `WaterfallViewModel.layout(of:limit:totalCount:now:)` — the static function both the full page
  and `TrafficStatsViewModel` build a `Layout` from, now that `limit` genuinely truncates rather
  than always equalling the input's own count: `Layout.count` reflects the rows actually produced,
  not the size of the array handed in. See [Amendments](#amendments) for why `limit` stopped being
  something every caller passed as `requests.count`.
- `TrafficStatsViewModel.recentLayout` and `.recentWaterfallCount` — that the section's own
  `waterfall` (whole log, feeding the caption) and `recentLayout` (capped) diverge correctly, that
  a log shorter than the cap shows everything it has rather than padding or hiding rows, and that
  the capped rows are the most recent ones, not an arbitrary five.

**Not unit-tested, and said plainly:** the pinch gesture itself, and its interaction with the
list's scrolling. Both are verified by hand on the simulator. This is the accepted cost of
choosing a gesture over a control, and the reason the arithmetic behind it was pulled into a
value type.

## Verification on device

Before the work is called done, on the simulator, with the example app's traffic:

1. Open the page against a log long enough to need it and confirm it arrives anchored on the
   newest traffic — the strip's window overlay already visible, narrower than the full strip —
   with the detail list's bars legibly different widths rather than a uniform floor. Open it
   against a short log and confirm it arrives showing the whole span instead, with no overlay: see
   [Default](#default) for the rule and why it changed from "always the whole span" to this.
2. Pinch in and confirm the detail zooms, the strip's window narrows to match, and rows leave the
   list as they leave the window.
3. Drag the strip from one end to the other and confirm the detail keeps up and never empties
   except over a genuine gap.
4. Confirm the zoom stops at both limits rather than continuing to scale.
5. Tap a row and confirm it opens that request's log detail.
6. On the Traffic Stats screen, confirm the Waterfall section's strip shows only the most recent
   `TrafficStatsViewModel.recentWaterfallCount` requests with legibly distinct bars — not the
   whole log compressed — and that the rows listed beneath it are those same requests, each
   opening its own log detail on tap. Confirm **See all** still opens the full page unchanged.
   This replaces the original item 6, "open the page from the Traffic Stats strip centred on the
   tapped point" — the strip lost its tap interaction entirely; see
   [Amendments](#amendments), "The Traffic Stats strip, zoomed instead of whole".
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
  account. The median came back afterwards, on its own, once the default-open rule below started
  needing it again — see the next amendment — and left a second time once that rule was itself
  replaced; see the final amendment in this list, and `WaterfallDurations`' own type documentation,
  "The median came back, then left again," for that full account too. The tail did not come back;
  nothing has needed it since.
- **The default window, reversed after device verification.** [Default](#default) above now
  describes this directly rather than only here, because it is not a small implementation drift —
  it is the one decision in "Decisions taken" this document treats as settled that the owner later
  overturned outright, on real traffic, after this spec and the code implementing it had both
  shipped. What was built and verified first was "opens honest, the whole span, zoom is the
  escape." Driven against an hour-long capture with two bursts of traffic an hour apart, every bar
  in the detail list rendered at the same 3pt floor regardless of whether the request took 43ms or
  1.06s, and the strip showed no window overlay at all — `marksASubset` is `false` at the whole
  span by design, so there was nothing on screen to suggest zooming was the answer. The owner
  reported this as the pinch appearing to do nothing, no highlighted section ever appearing, and
  every bar reading identical — three symptoms of the one root cause. The default now anchors the
  window on the newest traffic and sizes it so the *median* measured request is legible, clamped
  into the existing zoom limits, via `WaterfallWindow.opening(span:narrowest:medianMeasured:plotWidth:)`.
  A short log — the only kind the original default was ever checked against by hand — still opens
  at the whole span: the new rule is a narrowing of the old one for exactly the case that made the
  old one look safe, not an unrelated replacement of it. The old reasoning for "opens honest" is
  kept, not deleted, in [Default](#default) above, because it was not unsound reasoning — it was
  reasoning that a large enough log falsified, and that distinction is worth being able to see
  later.
- **The zoom gesture's attachment, again.** `.simultaneousGesture(_, including:)`, not
  `.gesture(_, including:)` — a second amendment to the same decision the previous gesture-related
  entry above already amended once. `.gesture(_:)` is SwiftUI's *lowest*-priority attachment: it
  only recognises once every other gesture in the responder chain has failed to. `WaterfallView`'s
  `List` owns a pan recogniser of its own, and on device that recogniser claims a pinch's touch
  sequence outright rather than ever failing, so the `MagnificationGesture` attached with
  `.gesture(_:)` never recognised at all — reported by the owner as the pinch doing nothing.
  `.simultaneousGesture(_, including:)` keeps the same `GestureMask` toggle the previous amendment
  valued `.gesture(_, including:)` for — `including: .subviews` still switches the pinch off
  without switching off the list's own gestures, once `WaterfallWindow.canZoom` is `false` — while
  dropping the requirement that the list's recogniser fail first. The attachment also moved, from
  the `List` itself to the `GeometryReader` that wraps it, on the judgement that a SwiftUI gesture
  attached to an ancestor of a UIKit-backed `List` is less likely to be arbitrated away by that
  `List`'s own internal `UICollectionView` gesture-recogniser subsystem — not a documented Apple
  guarantee, the more conservative of two reasonable places to attach it. Driving
  `WaterfallViewModel.zoom(by:)` also moved, from `.updating($lastMagnification)` to
  `.onChanged`/`.onEnded` against a plain `@State`: `.updating(_:body:)`'s own contract expects its
  closure to update only the gesture-state property it is attached to, not to push a side effect
  into a `@Published` property elsewhere, and that contract only got safe to lean past while a
  cancelled gesture could strand a plain `@State` with no `onEnded` to reset it — which stopped
  being possible once the gesture recognises independently rather than behind the list's own. See
  ``WaterfallView/magnification`` and ``WaterfallView/lastMagnification`` for the full reasoning.
  Not verified against a running app: no pinch-capable automation exists in this pipeline. The
  reasoning above, and confirmation that `WaterfallViewModel.zoom(by:)` is reachable and correct in
  isolation, is what backs this change; that the gesture actually recognises on device is for the
  owner to confirm.
- **The default window, revised a second time.** [Default](#default) above now describes this
  directly, in order, alongside both earlier rules — a second amendment to the same decision the
  previous "reversed after device verification" entry already amended once. What shipped after
  that first reversal opened the page anchored on the newest traffic, sized so the *median*
  measured request was legible. Driven against ordinary traffic rather than the hour-long capture
  that motivated it, that rule opened *too tight*: a 19-request session opened on `1 of 19`, a
  single median-legible request with nothing forcing the window any wider. The owner's instruction
  was direct — "size it to half the window" — and the rule now opens the page on half the series'
  span, anchored the same way, clamped into the same narrowest-and-widest limits, with no
  per-request duration entering the arithmetic at all. `WaterfallDurations.median(of:)`, which the
  second rule read for its "typical request" figure, has no remaining caller and was removed along
  with its four tests — see that type's own documentation, "The median came back, then left
  again," and `WaterfallWindow.opening(span:narrowest:)`'s own "Two rules before this one" for the
  full account of all three rules in order. Verified the same way the arithmetic always has been
  in this file: by test, against `WaterfallWindow.opening(span:narrowest:)` in isolation and
  through `WaterfallViewModel.configureWindow(plotWidth:)` end to end. Not verified visually —
  that the page now reads as opening on "about half" the traffic to someone looking at it is for
  the owner to confirm.
- **The Traffic Stats strip, zoomed instead of whole.** [Decision 4](#decisions-taken) and
  [Traffic Stats](#traffic-stats) above describe what shipped first: the section's strip built
  from the entire log, the same way the full page's minimap does, with a tap opening the page
  centred where the strip was touched. It was tried, shipped, and the owner judged it unusable at
  a real request count — twenty-five requests over twenty-four seconds rendered as a scatter of
  3pt specks, conveying rough shape and nothing about what had just happened, which is precisely
  what a Traffic Stats reader wants from this section. The owner's own words: *"maybe we show the
  waterfall here, zoomed to the last say...5 requests....and then show the last 5 below it."*
  The section now draws a small version of the full page instead of a compressed copy of it: the
  strip's drawn *range* is the most recent `TrafficStatsViewModel.recentWaterfallCount` requests,
  not the whole log with a subset merely marked on it — a marked-window reading was considered and
  rejected, because it would still compress the entire log onto the strip's width first, which is
  the exact defect being fixed, and would only additionally highlight a sliver of it — and those
  same requests are listed beneath it as rows, tappable through to each one's log detail.
  `recentWaterfallCount` is `5`: enough for every bar to read as its own request rather than a
  hairline, short enough to sit above the fold alongside the rest of the section, and small enough
  that "most recent" reads as obviously true of what is on screen rather than a rounding of a
  much larger recent-ish window; `10` was tried in reasoning and set aside as starting to crowd
  back toward the specks this change exists to remove.
  No second windowing concept was needed to zoom the strip: `WaterfallSeries.build(from:limit:now:)`
  already computes a series' origin and span from only the requests it is given, so passing it a
  five-request slice rather than the whole log is sufficient by itself. What changed was
  `WaterfallViewModel.layout(of:limit:totalCount:now:)`, the function already shared by every
  caller that builds rows, gaining a required `limit` parameter — no default, matching
  `WaterfallSeries.build`'s own established convention, because the full page and Traffic Stats
  deliberately disagree on how much of the log they want and no fixed figure or default could
  stand in for either. The same call now serves both: the full page passes `requests.count`,
  `TrafficStatsViewModel` passes `recentWaterfallCount`. Extending it this way, rather than giving
  `TrafficStatsViewModel` a second, parallel implementation, is what "do not duplicate the
  windowing logic" meant in practice. Fixing this also surfaced a latent bug: `Layout.count` had
  read `requests.count`, the size of the *input* array, rather than `rows.count`, how many rows
  the pass actually produced — harmless while every caller always passed `limit: requests.count`,
  silently wrong the moment one did not, and corrected alongside the rest of this change.
  The section's own detail rows reuse `WaterfallDetailRow` rather than a second row built to match
  it by eye: its shape needed no change to be reused this way, because it already took its
  `window` as a plain value rather than reaching into a specific view model, so a second caller
  supplying its own `WaterfallWindow(span: recentLayout.series.span, narrowest: 0)` — the widest
  window the row's bar-clipping arithmetic needs, not a zoom/pinch/scrub window in its own right —
  was already exactly what its existing parameters allow. The strip's tap interaction is gone
  rather than kept: `WaterfallView.init(logs:openingTime:)`'s mapping from a tapped moment to a
  centred window assumed the tapped strip's own series origin agreed with the full page's, true
  while the strip drew the whole log and false the moment it drew only the most recent five, whose
  origin is the earliest of just those five rather than the log's true earliest request. Reusing
  that mapping unchanged would have silently opened the full page centred on the wrong moment by
  however far the two origins had drifted apart; fixing the mapping itself would have meant
  changing `WaterfallView`'s own already-shipped, owner-approved contract for a caller that no
  longer needed the problem it solved. The five rows beneath the strip already give more precise
  navigation than "centred near where you tapped" ever did, so the strip now draws with
  `interaction: .none`, and `Interaction.tap(_:)` itself — `tapGesture(width:onTap:)` and
  `tapTolerance` with it — was deleted once that left it with no caller anywhere in the module; see
  the removal comment at the top of `WaterfallOverviewStrip.swift` for the account kept alongside
  the code, in the same style already used there for `WaterfallScrubGeometry`. The section's
  existing caption, `"N requests over X across Y hosts"`, is unchanged and still describes the
  whole log rather than the five requests drawn above it — kept deliberately rather than reworded:
  it never claimed to describe the strip specifically, every reword tried either repeated "N
  requests" awkwardly next to itself or left it ambiguous which count a trailing clause modified,
  and the section's own visual hierarchy — legible bars, tappable rows, **See all**, a footer with
  larger numbers than the five on screen — already communicates "this is a preview" without more
  words doing it again. This is a wording judgement, not a settled fact, and the owner may read it
  differently once it is on a device. Not verified on device: everything here is a visual and
  interaction judgement — whether five rows and a zoomed strip genuinely read better than the
  whole-log version they replace — and nothing in this pipeline can simulate the touches that would
  confirm it.
