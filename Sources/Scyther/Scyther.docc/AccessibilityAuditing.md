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
"Nothing Wrong vs. Nothing Looked At" below.

## Why the Accessibility Tree, Not the View Tree

The audit walks `UIAccessibilityElement`s and accessibility containers, not `subviews`. A SwiftUI
`Text` is not a `UILabel` — walking `subviews` under a SwiftUI hierarchy finds drawing layers with
no label and nothing to check. Walking the accessibility tree instead is what makes the audit work
uniformly over SwiftUI, UIKit, and any mixture of the two: it sees exactly what VoiceOver would see,
which is the whole point of an accessibility audit.

The walk skips Scyther's own UI. A label inside the Scyther menu, or one of its own overlays, is
never a finding — the audit is trying to tell you something about your app, not about itself.

The walk also gives up gracefully rather than hanging the app it's debugging: past a depth of 100
or 5,000 visited nodes it stops and marks the result as truncated, and the report says so — see
``AccessibilityAuditor/maximumDepth`` and ``AccessibilityAuditor/maximumNodes``.

## Missing Labels

An element carrying an interactive trait (button, link, adjustable) or an informative one
(image, search field, keyboard key) is flagged when its accessibility label is empty or
whitespace-only. **Static text is exempt** — a `UILabel` or SwiftUI `Text` with no explicit label
reads its own text content, so there's nothing to flag.

An element with no label can't be named in the report either, so it's identified by its type and
its position on screen instead — `Button at 24.0, 120.0` rather than nothing at all.

## Touch Targets

Every element carrying an interactive trait is measured against Apple's Human Interface
Guidelines minimum of **44 × 44pt**:

- Below **32pt** on its shortest side, it's an **error** — not slightly short, a miss.
- From **32pt up to 44pt**, it's a **warning** — worth a look, but a developer may have deliberately
  traded a little size for density.

The measurement is the element's frame in the window, not its hit-testing insets — a view that
extends its tappable area with `contentShape` or an invisible padding view already looks correct
to this check, exactly as it should.

## Contrast

Every element carrying a text-bearing trait (static text, buttons) is sampled against what's
actually drawn behind it, and measured against WCAG's thresholds:

- **4.5:1** for ordinary text.
- **3:1** when the element is at least **24pt tall** — a stand-in for WCAG's "large text" rule,
  which is defined in point size rather than anything the accessibility tree exposes. Height is
  the closest available estimate, stated as one rather than dressed up as the real rule.

### Contrast Is an Estimate

This is worth being plain about: **the reported ratio is sampled from pixels already on screen,
not computed from any color the code declared.** A `Color` or `UIColor` is not enough on its own —
a label over a photograph, a gradient, a blur, or another view showing through has no single
honest foreground/background pair, only whatever ended up rendered at that point. The audit
samples what was actually drawn and reports the ratio that produced, with the sampled foreground
and background colors named in the finding so you can judge the estimate yourself.

Treat a contrast finding as "worth a look," not as a certificate. It's always reported as a
**warning**, never an error, for exactly this reason.

## The Live Overlay

**Show Issues On Screen**, at the top of the report, draws a box around every current finding
directly over the running app — red for an error, orange for a warning — with a pill at the
bottom of the screen reporting the count. It re-audits automatically whenever the screen's layout
is likely to have changed, the same way ``GridOverlay`` and ``FPSCounter`` stay live without a
developer manually refreshing them.

The overlay doesn't swallow touches: only the count pill itself is interactive, so you can keep
using the app underneath with the boxes on screen.

Tapping a finding's row in the report flashes its box on the live overlay, so the row you're
reading and the element on screen are never in doubt.

## The Report Is Frozen

The report doesn't move while you're reading it. It runs once, when the screen first appears, and
stays exactly as that pass left it — including if you switch a check on or off, or interact with
the app underneath — until you tap **Re-run**. A report that reflows under a developer mid-read
is worse than a stale one that says plainly when it was taken.

### Nothing Wrong vs. Nothing Looked At

An empty report can mean two different things, and the screen never lets them read the same way:
every enabled check passed, or a check was switched off before the audit ran. When any check was
skipped, the empty state names exactly which ones didn't run, rather than letting their absence
be mistaken for a clean bill of health.

## See Also

- ``AccessibilityAuditView``
- ``AccessibilityAuditViewModel``
- ``AccessibilityAuditor``
- ``AccessibilityCheck``
- ``AccessibilityFinding``
- ``AccessibilitySeverity``
