# Accessibility Audit — Design

**Date:** 2026-09-06
**Status:** Approved

## Goal

Show the developer, on the screen they are looking at, the accessibility defects a VoiceOver
user or a Switch Control user would hit: elements with no label, touch targets under Apple's
44pt minimum, and text whose contrast falls below WCAG AA.

The toolkit already ships overlays that draw over the running app (grid, FPS counter, touch
visualiser). This is another, with one difference: it produces *findings*, so it also needs a
place to read them.

## Non-Goals

Out of scope for this version, and deliberately so — each is a feature in its own right, and
shipping three checks that are right beats shipping six that are noisy:

- Dynamic Type overflow and truncation.
- Overlapping or occluded hit targets.
- Trait correctness (a button that reports itself as static text).
- Anything off-screen, in another window, or behind a modal.
- VoiceOver focus order.
- Exporting findings. The bug report bundle, when it is built, is where that belongs.

## Placement

`Sources/Scyther/Features/AccessibilityAudit/`, reached from **UI/UX** in the menu, beside
Grid Overlay, FPS Counter and Touch Visualiser. It is an interface tool and it belongs with
the other interface tools.

## Architecture

Six units, each with one job.

| File | Responsibility |
| --- | --- |
| `AccessibilityAudit.swift` | The singleton the menu and `InterfaceToolkit` talk to: the live toggle, which checks are enabled, and persistence. Mirrors `GridOverlay`. |
| `AccessibilityAuditor.swift` | The walk and the checks. Pure over ``AuditNode``; knows nothing about UIKit windows. |
| `AuditNode.swift` | The protocol the auditor walks, plus the `UIView`/`NSObject` conformance that adapts the real accessibility tree to it. |
| `AccessibilityFinding.swift` | One defect: its check, severity, screen frame, a human sentence, and whatever the check measured. |
| `AccessibilityAuditOverlayView.swift` | The `TopLevelView` that draws the boxes and the count pill. |
| `AccessibilityAuditView.swift` + `AccessibilityAuditViewModel.swift` | The report screen. |

`InterfaceToolkit` gains `setupAccessibilityAudit()` and `showAccessibilityAudit()`, exactly
as it has for the grid overlay, and adds the overlay to `topLevelViewsWrapper`.

### Why the accessibility tree, not the view tree

A SwiftUI `Text` is not a `UILabel`; it is drawn into a layer by the rendering system, and a
walk over `subviews` finds a `_UIGraphicsView` with no label, no traits and nothing to check.
The accessibility tree is what VoiceOver reads, it is identical in shape for UIKit and
SwiftUI, and it is the only tree in which a finding means anything to a user.

The walk starts at the key window and, for each node:

1. If the node is an accessibility element (`isAccessibilityElement`), it is a leaf: check it.
2. Otherwise, if it exposes accessibility children (`accessibilityElementCount() > 0`),
   descend into `accessibilityElement(at:)`.
3. Otherwise, if it is a `UIView`, descend into `subviews`.

Nodes are skipped, without descending, when they are hidden, fully transparent, have an empty
frame, sit outside the window's bounds, or belong to Scyther itself — the menu, any Scyther
sheet, and the `TopLevelViewsWrapper` — because a tool that audits its own UI reports
findings the developer cannot act on.

Depth is capped at 100 and total nodes at 5,000. A pathological hierarchy must not hang the
app; the report says when a cap was hit rather than silently reporting a partial result as
complete.

## The Checks

Each check is a value in `AccessibilityCheck`: `missingLabel`, `touchTarget`, `contrast`.
Each can be switched off individually, and a check that is off is not run at all.

### Missing label

Fails when a node is an accessibility element, carries at least one of the traits
`.button`, `.link`, `.image`, `.searchField`, `.adjustable` or `.keyboardKey`, and its
`accessibilityLabel` is nil, empty, or only whitespace.

Static text is exempt: its content is its label. An element hidden from accessibility is
exempt: it was hidden on purpose, and decorative images are the reason the API exists.

Severity: **error**. A control VoiceOver cannot name is a control it cannot use.

### Touch target

Fails when a node is an accessibility element, carries `.button`, `.link` or `.adjustable`,
and its `accessibilityFrame` is narrower or shorter than 44pt.

The finding reports the measured size, rounded to one decimal, so the developer can see how
far off it is: `32.0 × 32.0pt, under the 44 × 44pt minimum`.

Severity: **warning** at 32pt and above, **error** below it. Something can be a few points
short by design; something half the minimum is a miss.

### Contrast

Runs for nodes carrying `.staticText` or `.button` with a non-empty label — the elements that
draw text. One `UIGraphicsImageRenderer` snapshot of the key window is taken per audit pass,
and each element's frame is cropped out of it. Per element:

1. Downsample the crop to at most 64 × 64 to bound the work.
2. Compute each pixel's relative luminance (WCAG's sRGB formula, with the standard
   linearisation).
3. Split the pixels at the midpoint between the darkest and lightest luminance present; the
   larger group by pixel count is the background, the smaller is the foreground.
4. Take each group's mean colour, and compute `(L1 + 0.05) / (L2 + 0.05)`.

Fails below **4.5:1**, or below **3:1** when the element's frame is at least 24pt tall, which
is the closest an outside observer can get to WCAG's "large text" without knowing the font.

The finding reports the ratio to one decimal and both sampled colours as hex, and says in
words that it is an estimate: a glyph over a photograph or a gradient has no single honest
ratio, and the developer needs to know which findings to trust.

Severity: **warning**, always. The measurement is an estimate, and an estimate does not get to
call itself an error.

Elements are skipped when the crop is empty, entirely one colour, or lies outside the window.

## Live Mode and the Report

One auditor, two consumers, one pass feeding both.

**Live mode** (off by default) draws a rounded box per finding over the running app, tinted by
check — errors red, warnings amber — with a small count pill at the bottom that opens the
report. It re-audits on `UIWindow.didBecomeVisibleNotification`, on device rotation, and on
the wrapper's own layout pass, coalesced behind a 0.5s debounce so that a screen animating in
audits once when it settles rather than forty times on the way. It never audits per frame.

The overlay is not interactive except for the pill: boxes are `isUserInteractionEnabled =
false`, so the app underneath stays usable.

**The report** is pushed from the menu row and shows the findings of the pass that was live
when it opened, or runs one pass on appear when live mode is off. It is frozen: no re-walk
while it is up, because findings that move while they are being read are useless. It carries a
**Re-run** button for when the developer wants a fresh pass.

Findings are grouped by check, each row naming the element (its label, or its class and frame
when it has none) over what the check measured. Tapping a row flashes that element's box on
the overlay behind. An empty result gets a `ContentUnavailableView` saying the screen passed
the checks that ran, and naming any check that was switched off — "no findings" must never be
mistaken for "nothing was looked at".

## Settings and Persistence

`UserDefaults.scyther`, keys namespaced as the toolkit's are:

| Key | Default |
| --- | --- |
| `Scyther_accessibility_audit_live` | `false` |
| `Scyther_accessibility_audit_missing_labels` | `true` |
| `Scyther_accessibility_audit_touch_targets` | `true` |
| `Scyther_accessibility_audit_contrast` | `true` |

The menu row shows the live state, so the overlay is never quietly on.

## Safety

The audit is off inside an XCTest process and on App Store builds, through the same
`AppEnvironment` checks the rest of the toolkit uses. It walks and draws on the main actor,
because UIKit accessibility properties can only be read there. Nothing it does mutates the
app: no traits are set, no frames are changed, and the overlay never takes touches except on
its own pill.

## Localisation

Every user-facing string goes through `localized(_:)`, with keys added to a new
`Scripts/localization/strings/AccessibilityAudit.json` fragment in all twelve languages, and
the catalogue rebuilt. Measurements — sizes, ratios, hex colours — are formatted, not
translated, and any sentence that embeds one is a single key with an interpolation so its word
order can change with the language.

## Testing

- **The checks** are pure functions over `AuditNode`, so a test builds a tree of doubles with
  chosen traits, labels and frames and asserts the findings. No window, no simulator UI.
- **The walk** is tested for the skip rules, the descent order, and both caps.
- **Contrast** takes an injectable sampler, so a test hands it known bitmaps — black on white,
  grey on grey, a gradient — and asserts the ratios and which side was called the background.
- **The view model** is tested for grouping, the frozen-until-re-run behaviour, and the empty
  state naming disabled checks.
- **The settings singleton** is tested against a throwaway `UserDefaults` suite, as the other
  overlay settings are.

## Verification on device

The example app gets a screen with deliberate defects — an unlabelled icon button, a 30pt tap
target, and light grey text on white — so the audit can be seen finding all three, and so the
overlay, the pill, the report and the row-to-box flash can be exercised by hand before the
work is called done.
