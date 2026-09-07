# Accessibility Auditing

Find missing VoiceOver labels, undersized touch targets, and low-contrast text before a reviewer or a user does.

@Metadata {
    @PageColor(green)
}

## Overview

**UI/UX → Accessibility Audit** walks the screen that's actually on device and reports what a
VoiceOver user or someone with low vision would run into. It is not a linter over your source —
it inspects the live accessibility tree, so it catches what your code actually produced, including
whatever a third-party component or a `UIKit` view buried inside a `UIViewRepresentable` did on
its own.

Three checks run independently, each switchable from the toggles at the top of the report screen:

- **Missing Labels** — an element VoiceOver would read with no name
- **Touch Targets** — a control smaller than a comfortable finger target
- **Contrast** — text whose colour is too close to what's behind it

A check that's switched off is not run at all, and the report says so explicitly — see
"Nothing Wrong vs. Nothing Looked At" below. Read
<doc:AccessibilityAuditing#What-the-Audit-Cannot-See> before you read a clean report as good news.

### Two Checks Live, Three in the Report

**The live overlay runs Missing Labels and Touch Targets. The report runs all three.** That is not
an oversight and it is not configurable — it is the difference between a pass that runs unasked and
one you asked for.

Missing Labels and Touch Targets read the accessibility tree and the geometry of what is on screen.
Contrast reads *pixels*, and getting those pixels means rasterising the entire window with
`drawHierarchy(in:afterScreenUpdates: true)` — a forced full re-render on the main thread. On a real
screen that measured **436ms of an 800ms pass**. The live overlay takes a pass on every navigation,
so with contrast on that path the app froze for most of a second every time you pushed, popped or
switched tab, for an answer you were not looking at yet.

So contrast is measured at the two moments you asked for it: when you **open the report**, and when
you tap **Re-run**. Opening the report from the count pill takes the contrast pass in the instant
before the sheet appears, while your app is still the thing on screen — which is also the only
moment it can be measured honestly, since a presented sheet dims and scales everything behind it.

Two consequences worth knowing:

- **The pill counts two checks; the report counts three.** The numbers are meant to differ. The pill
  is a live count of what live mode checks.
- **Contrast findings get no live box.** A contrast finding exists only in a report, so tapping its
  row does not flash a box over the app the way a label or touch-target row does.

The report never leaves this implicit. Every report carries a line naming the checks that ran and
the time they ran at — `Missing Labels, Touch Targets measured at 10:42:11` — so a contrast result
on screen is dated, and a report with no contrast in it is visibly not claiming one. When a check is
switched on but is not in the pass you are reading, a banner says so and points at **Re-run**.

## Why the Accessibility Tree, Not the View Tree

The audit walks `UIAccessibilityElement`s and accessibility containers, not `subviews`. A SwiftUI
`Text` is not a `UILabel` — walking `subviews` under a SwiftUI hierarchy finds drawing layers with
no label and nothing to check. Walking the accessibility tree instead is what makes the audit work
uniformly over SwiftUI, UIKit, and any mixture of the two: it sees exactly what VoiceOver would see,
which is the whole point of an accessibility audit.

The walk skips Scyther's own UI. A label inside the Scyther menu, or one of its own overlays, is
never a finding — the audit is trying to tell you something about your app, not about itself.

That decision is made structurally rather than by class name. Each node is walked up its responder
chain to whichever view controller owns it, and everything Scyther presents is hosted in a
controller marked as Scyther's; Scyther's non-presented overlays are recognised by their own
`TopLevelView` base class. Naming was tried and did not work: every Scyther screen is SwiftUI, so
the view it hangs off is `_UIHostingView<…>`, a private SwiftUI type mentioning Scyther nowhere —
which is how the audit came to draw red error boxes over Scyther's own close button. The live
overlay uses the same answer from the other side and draws nothing at all while a Scyther screen
is in front of the app.

The walk reports only what can actually be seen. It honours `accessibilityElementsHidden` and
`accessibilityViewIsModal`, and it skips a recycled cell scrolled out of a table, a parked carousel
page, anything clipped away by an ancestor, and anything an opaque view is drawn on top of. Every
one of those asks the same single question — "can this be seen?" — so a container the walk prunes is
never one the report has already counted.

### The Pass Is Bounded Three Ways

The walk gives up gracefully rather than hanging the app it's debugging. Three limits stop it:
``AccessibilityAuditor/maximumDepth`` (100), ``AccessibilityAuditor/maximumNodes`` (5,000 nodes
*touched*, including the ones the visibility rules then discard) and a wall-clock budget covering
the whole pass — the window snapshot and the per-element pixel sampling included, not just the tree
walk.

The budget is a different number for each kind of pass, because they do different amounts of work
and you are in a different posture for each. ``AccessibilityAuditor/budget`` is **0.25s** and bounds
the live pass, which runs unasked while you navigate; ``AccessibilityAuditor/reportBudget`` is
**2s** and bounds a report pass, which has a window snapshot in it and which you are waiting for.
The clock starts before the snapshot and is read again the moment it returns, so a capture that
spends the whole budget stops the pass and raises the same truncation banner every other limit
raises — rather than being excluded from the one bound on how long your app is held.

Any of the three stopping the pass puts a banner at the top of the report. Read what it says
carefully: **the limits abandon the whole remainder of the tree in tree order, not the branch they
fired on.** A list holding a few thousand scrolled-away cells can exhaust the node budget inside the
table, and the toolbar and tab bar below it are then never looked at at all. What is missing from a
truncated report is unchecked, not clean.

## Missing Labels

Any element VoiceOver will land on is flagged when its accessibility label is empty or
whitespace-only. The rule is an **exemption list**, not a trait list, and there are two exemptions:

- **Static text** reads its own content, so there is nothing missing.
- **An element with an accessibility value** reads that instead.

Everything else with `isAccessibilityElement` set is checked, whatever its traits. Gating on traits
instead — the way this began — meant a custom control whose author set `isAccessibilityElement` and
then set nothing else was checked by nothing at all, which is the half-finished job this rule most
needs to catch.

An element with no label can't be named in the report either, so it's identified by its type and
its position on screen instead — `UIButton at 24.0, 120.0` rather than nothing at all.

## Touch Targets

Every element carrying an interactive trait (button, link, adjustable) is measured against Apple's
Human Interface Guidelines minimum of **44 × 44pt**:

- Below **24pt** on its shortest side, it's an **error** — not slightly short, a miss. 24 is WCAG
  2.5.8 Target Size (Minimum) at AA, and it is the only number in this rule anyone can cite: HIG
  says 44, WCAG 2.5.5 (AAA) says 44, WCAG 2.5.8 (AA) says 24.
- From **24pt up to 44pt**, it's a **warning** — short of the platform's guidance but not of any
  standard, and something a developer may have deliberately traded for density.

The two severities cite the two different numbers, so an error reads "under WCAG 2.5.8's 24 × 24pt
minimum" and a warning "under Apple's 44 × 44pt guidance".

**A link is never more than a warning, however small it is.** WCAG 2.5.8 carries an explicit
exception for a target "in a sentence or block of text", and an inline link's frame is its glyph
run — around 18pt tall. Nobody makes body-copy links 44pt, so calling one an error is an
unactionable red box.

The measurement is the element's frame in the window, not its hit-testing insets — a view that
extends its tappable area with `contentShape` or an invisible padding view already looks correct
to this check, exactly as it should.

## Contrast

Text is measured against what is actually drawn behind it, at WCAG's thresholds:

- **4.5:1** (WCAG 1.4.3) for ordinary text.
- **3:1** for large text — WCAG's real rule, **18pt or 14pt bold**, read off the element's font
  rather than guessed from how tall its frame happens to be. A `UILabel`, `UIButton`, `UITextField`
  or `UITextView` can be asked, including the smallest run of an attributed string and the size a
  label that `adjustsFontSizeToFitWidth` can shrink to.
- **3:1** (WCAG 1.4.11) for non-text content — an icon-only button, or an element carrying `.image`.

Where the point size cannot be read, the **strict** threshold stands rather than being guessed at,
and the finding says so: the relaxation can only ever hide a failure. Only an element that can
*affirmatively* say it draws no text earns the non-text grade, so a SwiftUI `Button("Continue")`,
which cannot, keeps the strict one. A disabled control is not graded at all — WCAG 1.4.3 exempts
inactive components outright.

The check is not gated on traits. A `UITableViewCell`, or a SwiftUI row that makes itself one
VoiceOver stop, carries neither `.staticText` nor `.button`, and gating on those meant that on a
list screen — the most ordinary screen in iOS — no text was sampled at all and the report printed a
green tick. Where the element is a real view the check descends into it **for sampling only**, and
measures each `UILabel`/`UITextField`/`UITextView` at its own bounds, so the finding boxes the label
that failed rather than the whole row. One element still produces at most one finding: the worst
region.

Where there is nothing to descend into, the element's **own frame** is measured. That is not an edge
case — it is every SwiftUI screen. SwiftUI draws text into private layers and hangs synthetic
`UIAccessibilityElement`s off the hosting view, so a descent looking for text-drawing `UIView`s
finds nothing on a `List` of `Text`, and making the descent the only route to a measurement would
take contrast off the commonest UI framework in use entirely. The rule is: descend when there is
something to descend into, otherwise measure the element itself. An accessibility element carrying a
non-empty label that is not an image is text as far as this check is concerned, whatever framework
drew it.

### Contrast Is an Estimate

**The reported ratio is sampled from pixels already on screen, not computed from any colour the code
declared.** A `Color` or `UIColor` is not enough on its own — a label over a photograph, a gradient,
a blur, or another view showing through has no single honest foreground/background pair, only
whatever ended up rendered at that point.

The crop's pixels are clustered into two tonal groups, and each group is represented by the colour
*most* of it actually is — not by its mean, which antialiased glyph edges drag toward the page, and
not by its darkest or lightest pixels, which any icon or gradient inside the frame can define. That
is what lets `#767676` on white, WCAG's canonical exactly-passing grey, report 4.54:1 rather than
being failed, and what stops a `#333333` icon covering 3% of a label's frame hiding `#949494` text
at a real 3.03:1.

**A crop with no such structure is refused rather than estimated.** Text on a gradient, text on a
photograph, a glyph the sampler only caught at partial coverage, and a pair too close together to
distinguish from the capture's own dither all come back as **could not be measured** — which is
reported as its own state, and is not a pass. Treat a contrast finding as "worth a look," not as a
certificate. It's always reported as a **warning**, never an error, for exactly this reason.

The snapshot the check reads is constrained three ways worth knowing about if a ratio ever looks
wrong: it never contains Scyther's own drawing, it never contains content iOS protects (secure text
entry, DRM, Apple Pay — when `drawHierarchy` declines there is no fallback and contrast is reported
as unmeasurable), and it is captured at no more than 2 pixels per point.

## The Live Overlay

**Show Issues On Screen**, at the top of the report, draws a box around every missing-label and
touch-target finding directly over the running app — red for an error, orange for a warning — with a
pill down the **trailing edge** of the screen reporting the count. Contrast is not in a live pass;
see <doc:AccessibilityAuditing#Two-Checks-Live-Three-in-the-Report>. The pill sits on the side rather than the
bottom deliberately: it is the one thing Scyther puts over your app that takes touches, and at the
bottom centre it sat on top of tab bars and primary action buttons and took their taps.

The overlay doesn't swallow anything else: only the count pill itself is interactive, so you can
keep using the app underneath with the boxes on screen.

It follows the app by watching it lay out. Anything that changes what is on screen lays something
out — a push lays out the incoming view, adding a subview marks its new superview as needing layout,
a scroll lays out on every frame it tracks, a reload lays out the cells that changed — so a tab
switch, a push, a swipe-back, a sheet of your own and a scroll that comes to rest all re-audit, half
a second after the screen stops moving. Scyther already swizzles `UIView.layoutSubviews` for the
view-borders overlay, so this costs no new hook.

It watches layout rather than which view controllers are showing, which is what it used to do. That
question has an honest answer in a UIKit app and almost none in a SwiftUI one: a `TabView` switch, a
`NavigationStack` push and a `List` scroll all happen inside one `UIHostingController`, so the chain
never moved and the overlay drew one pass at launch and then described a screen that had gone.

Nothing runs while you are still moving. Every layout restarts the half-second debounce, so the pass
lands once the screen settles — with one deliberate exception: a screen that *never* settles (a
spinner, a video layer, an auto-advancing carousel) would otherwise defer the pass for ever, so a
pass is let through after two seconds of unbroken movement. On a long scroll that means one live
pass — about 121ms — roughly every two and a half seconds, which is the price of the boxes ever being
right on a screen that never stops.

A pass cannot make itself run again. Everything the overlay draws — the boxes, the pill, the flash —
lives inside Scyther's own top-level view wrapper, and a layout in there is ignored; and a pass that
found what the last one found repaints nothing at all, so there is nothing to lay out either way.

What it does *not* notice is content that changes with no `UIView` laying out at all. Those keep the
last pass's boxes; tapping the pill takes a fresh pass, which is the way out of any stale one.

Tapping a finding's row in the report flashes its box on the live overlay. Because the report is
always in front of the app, the flash waits until you close it and then plays over the app itself.

**Nothing at all is installed or scheduled on a build the audit may not run on** — no overlay in the
hit-testing chain, nothing watching the app lay out, no pass. See <doc:AccessibilityAuditing#Never-on-an-App-Store-Build>.

## The Report Is Frozen

The report doesn't move while you're reading it. It runs once, when the screen first appears, and
stays exactly as that pass left it — including if you switch a check on or off, or interact with
the app underneath — until you tap **Re-run**. A report that reflows under a developer mid-read
is worse than a stale one that says plainly when it was taken.

Opened from the pill it opens onto a pass taken in the instant before the sheet appeared — while
your app, not Scyther, was on screen — rather than taking one from underneath itself. That pass runs
all three checks; the brief pause before the report appears is the window snapshot contrast needs.

Every pass carries the moment it was taken, and every report shows it: a line naming the checks that
ran and the time they ran at. A report showing a pass from before this screen opened also says so
and shows its age, because "this is the last pass over your app" and "this is your app now" are
different claims — and a contrast ratio for a row you have since scrolled past is exactly the kind of
claim that needs a date on it.

Opened from **UI/UX → Accessibility Audit** inside the menu there was no such instant: Scyther was
already covering the app before you got there. Such a report seeds off the last live pass if there
is one, and contrast is reported as not run rather than measured through Scyther's own dimming.

### Nothing Wrong vs. Nothing Looked At

An empty report can mean four different things, and the screen never lets them read the same way:

- **Findings hidden.** The pass found things and the toggles are hiding all of them.
- **Nothing was checked.** Every check switched off, or every check refused.
- **No issues in what was checked.** Something ran, but not everything: a check switched off,
  skipped while Scyther covered the app, unmeasurable, or able to read only part of the screen — or
  a walk a limit stopped early.
- **No issues found.** The one case that earns a tick, and even it says what the audit cannot see.

A check that could read **nothing at all** — a capture the system refused, or a screen captured fine
on which nothing was legible — is reported as exactly that, never as a pass.

A check that read **some** of the screen keeps what it found and states its coverage: *Contrast read
3 of 41 elements on this screen.* The two are separated deliberately. The analyser refuses any crop
it cannot trust — a gradient, a photograph, a glyph it only caught at partial coverage — so on a
screen made mostly of those, contrast can measure a handful of elements and find a genuine defect in
one of them. Calling that pass unmeasurable, as an earlier rule did whenever fewer than half the
candidates came back readable, described a report containing a real finding as one containing no
result at all. Both banners close on the same sentence, because the consequence for the reader is
the same: what was not measured is missing from the report, not passing it. Partial coverage still
costs the tick, so a clean result is never mistaken for a guarantee.

## What the Audit Cannot See

A clean report is not a statement that your app is accessible. It is a statement that three specific
checks found nothing on one screen as it looked at one moment. These are the gaps, and none of them
is a bug:

- **Anything your app never exposed to accessibility.** The audit walks the accessibility tree, so
  an element that is not in it does not exist as far as this tool is concerned. A custom control
  drawn into a view with no `isAccessibilityElement`, an image with `accessibilityElementsHidden`
  set on its container, a view VoiceOver simply never reaches — all of them pass silently, and all
  of them are exactly the defect a VoiceOver user hits. This is the largest gap by far.
- **Whether a label *means* anything.** The Missing Labels check tests that a label exists and is
  not whitespace. "Button", "image1" and "asdf" all pass it. No tool can judge whether a name
  describes what the control does; only you and a VoiceOver user can.
- **Non-text contrast beyond a flat element's own frame.** WCAG 1.4.11 covers icons, control
  boundaries, focus indicators and meaningful graphics. This measures a two-tone crop, so it reports
  on an icon on a plain background and refuses a photograph, a gradient or a chart — refusing is
  honest, but it is not coverage.
- **Any appearance that is not currently on screen.** Light or dark mode, whichever you are not in.
  Every Dynamic Type size other than the one set right now. Every locale other than the current one,
  including the right-to-left layouts and the long German strings that break real layouts. Increased
  Contrast, Reduce Transparency, Bold Text, Button Shapes, Reduce Motion.
- **Anything off screen.** Everything below the fold of a scroll view, every row of a list not
  currently laid out, every screen you have not navigated to, and — after a truncated pass —
  everything after the stopping point in tree order.
- **Contrast, while you are only watching the live overlay.** The boxes and the pill cover two of
  the three checks. A screen you never opened the report on has not had its contrast measured at
  all, and the pill reading zero says nothing about it.
- **Everything the three checks are not.** VoiceOver reading *order*, focus traps, custom rotors,
  accessibility actions, hint quality, Switch Control and Voice Control reachability, captions,
  haptics, timing and motion. None of it is measured here.

Contrast findings are estimates from rendered pixels, and touch-target findings measure drawn frames
rather than hit-testing insets — so a finding can be wrong in the harmless direction too. Use the
audit to find defects; do not use it to certify their absence.

## Never on an App Store Build

Every other Scyther feature is gated by `Scyther.start()` alone. The audit refuses on its own account
as well: on an App Store build it does not run even with `Scyther.start(allowProductionBuilds: true)`,
because it is the only feature that reads the user's screen as pixels. On such a build no overlay is
installed, nothing watches the app lay out, and no trigger — including the notification observers
registered at launch — can schedule a pass.

## See Also

- ``AccessibilityAuditView``
- ``AccessibilityAuditViewModel``
- ``AccessibilityAuditor``
- ``AccessibilityCheck``
- ``AccessibilityFinding``
- ``AccessibilitySeverity``
