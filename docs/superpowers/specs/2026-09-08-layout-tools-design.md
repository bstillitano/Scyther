# Layout Tools — Design

**Date:** 2026-09-08
**Status:** Approved

## Goal

Answer two questions a developer asks constantly and currently cannot ask the app itself:

1. **Is that gap the 16 points I specified?** — a ruler that measures between two points, snapping to real view edges.
2. **Where does the safe area actually end?** — a static overlay drawing the key window's safe-area insets and layout margins.

Both are drawn over the running app, both live under **UI/UX** beside the grid overlay, and both are shipped together because the second is small and belongs beside the first.

## Non-Goals

Each is a feature in its own right and none is needed to make these two useful:

- The view hierarchy inspector. It is the next spec, and it inherits the hit-testing this one builds.
- Editing anything. These tools measure and draw; they never change a frame, a constraint or a colour.
- Measuring across time, recording measurements, or exporting them. A measurement answers a question and is then thrown away.
- Anything off-screen, in another window, or behind a modal.
- Constraint inspection. Knowing *why* a gap is 23 points is the inspector's job, not the ruler's.

## Decisions taken

Settled with the owner before this document was written. Each is here because it shapes the rest, and reversing one changes the others.

1. **Two specs, not one.** The layout ruler and the view hierarchy inspector are separate subsystems. The ruler goes first: it is Effort M against XL, and it is the first Scyther overlay that accepts touches, so it establishes the hit-testing and point-picking the inspector will need for tap-to-select. Shipping the cheap one first also de-risks the expensive one — this project's recent history is that large interface features get rebuilt once after being driven by hand.
2. **The ruler snaps to view edges, with a free mode.** Snapping is the default because the question is "is this the 16 points I specified", and a number that depends on how steady a thumb was cannot answer it. Free measurement stays available for the cases with no edge to snap to — into whitespace, or to a point inside an image.
3. **The safe-area and layout-margin guides are their own toggle**, beside Grid Overlay, not part of the ruler. They are guides you want visible while *using* the app — scrolling, navigating, watching a layout misbehave. Tying them to the ruler would show them only while an overlay is eating your touches, which is precisely when you cannot drive the app.

## Layout Guides

A `TopLevelView` subclass, toggled from the menu, drawing over the key window:

- **Safe-area insets** — a line at each inset that is non-zero, labelled with its value in points.
- **Layout margins** — the key window's root view's `layoutMargins`, drawn in a second colour and labelled the same way.

No touches, no state beyond a `UserDefaults` flag, redrawn on `updateFrame()`. It mirrors `GridOverlayView` closely enough that the existing file is the reference for how to build it.

Insets of zero are not drawn: a line labelled `0.0 pt` flush against the screen edge is noise, and on a device with no home indicator the bottom inset genuinely is zero.

### Settings

`UserDefaults.scyther`, namespaced as the toolkit's other overlays are:

| Key | Default |
| --- | --- |
| `Scyther_layout_guides_enabled` | `false` |

The menu row shows the state, so the overlay is never quietly on.

## Layout Ruler

A menu row that dismisses the menu and activates an overlay which takes touches.

### Measuring

Drag anywhere on screen. The overlay draws a line between the drag's start and current point, with the distance in points at its midpoint.

**In snap mode** each endpoint attaches to the nearest edge of the view under that point, so a drag roughly between two labels reports the real gap between them. The readout names what it measured — `Title.bottom → Subtitle.top`, then the distance.

**In free mode** the endpoints stay exactly where the fingers were, and the readout carries the distance alone.

A measurement persists after the finger lifts so it can be read, and is replaced by the next drag. There is no history.

### The control

A floating control, always visible, carrying:

- **Done**, which dismisses the overlay.
- A **Snap / Free** picker, a stock segmented `Picker`.

Done matters more than it looks. The overlay consumes touches, so without a visible way out the only exit is the shake gesture — which does still work, because shake is a motion event rather than a touch, but a developer who does not know that is stuck in a debugging tool. The control sits at the bottom of the screen, clear of the status bar and the typical navigation bar.

### What the ruler must not measure

The probe skips Scyther's own interface — the menu, any Scyther-presented sheet, and `TopLevelViewsWrapper` including the ruler's own overlay and control. Measuring the ruler against itself is the obvious failure, and the marker protocol and skip rule for this already exist: ``ScytherPresentedUI`` and the ownership test the accessibility audit uses. This reuses them rather than inventing a second answer that can drift from the first.

### Settings

Activation is not persisted. A ruler that survives a relaunch is a debugging tool the developer has to remember switching off; the mode picker's position is not worth persisting either, since snap is the default answer and the session is short.

## Architecture

`Sources/Scyther/Features/LayoutTools/`:

| File | Responsibility |
| --- | --- |
| `LayoutGuides.swift` | The settings singleton for the static overlay. Mirrors `GridOverlay`. |
| `LayoutGuidesView.swift` | The `TopLevelView` drawing safe-area insets and layout margins. |
| `LayoutRuler.swift` | The ruler's activation and mode state. |
| `LayoutRulerOverlayView.swift` | The interactive `TopLevelView`: the drag, the drawn measurement, the control. |
| `LayoutRulerGeometry.swift` | **Pure.** Snap-target selection, distance, and where the label sits. |
| `ViewProbe.swift` | Finds the host view under a point, skipping Scyther's own. |

`InterfaceToolkit` gains `setupLayoutGuides()` and `showLayoutRuler()`, exactly as it already has for the grid overlay and the accessibility audit, and adds both views to `topLevelViewsWrapper`.

### Why the geometry is a separate pure type

An overlay's drawing cannot be inspected by a test, and a gesture cannot be driven by one. This project has now hit that wall three times — `WaterfallStripGeometry`, `WaterfallDetailGeometry`, and a scrub-direction check that was extracted for exactly this reason — and each time the answer was the same: put the arithmetic in a pure type the test can reach, and reduce the view to calling it.

`LayoutRulerGeometry` therefore owns every decision that has a right answer: which edge of a hit view is nearest a point, what the distance between two points is, whether a label would fall off screen and where it goes instead. The overlay draws what it returns and decides nothing.

### The probe

`ViewProbe` answers one question: which host view is under this point?

It walks the key window's hierarchy front-to-back, skipping any view that is hidden, fully transparent, outside the window's bounds, or owned by Scyther. It returns the deepest match, because a developer pointing at a label means the label, not the stack that contains it.

**The accessibility audit's cost lesson applies and must not be relearned.** That feature hung the app by asking every view for its accessibility children, because doing so forces UIAccessibility to compute a subtree recursively. `ViewProbe` walks `subviews` and reads `frame`, `isHidden` and `alpha` — all cheap stored properties — and must never touch the accessibility tree. A probe runs per touch-move, so it is on a far hotter path than the audit ever was.

## Edge cases

| Case | Behaviour |
| --- | --- |
| No key window | Neither tool activates; the menu row reports it rather than appearing to work. |
| Snap finds no view under a point | That endpoint falls back to the free point, and the readout says so rather than reporting a snap that did not happen. |
| Both endpoints on the same view | Measured normally — measuring a view's own height is a legitimate question. |
| A view smaller than the touch | The probe returns the deepest match under the point's centre; no minimum size. |
| Rotation mid-measurement | The measurement is cleared. Its endpoints described a layout that no longer exists. |
| Content scrolls under a finished measurement | The measurement is left where it was drawn and does not follow. It is a snapshot of an answer, and moving it would silently make it wrong. |
| Zero-length drag (a tap) | No measurement drawn. A tap is how you dismiss the readout. |

## Accessibility

The ruler is a direct-manipulation tool with no non-visual equivalent, and this is worth stating plainly rather than pretending otherwise: a measurement between two points on a screen is not meaningful to a screen reader, and a VoiceOver user cannot perform the drag that produces one.

What it must do is not *break* anything: the overlay carries `accessibilityViewIsModal` while active so VoiceOver does not wander into the app underneath it, and the Done button is a properly labelled, focusable control so the tool can always be escaped. Layout Guides draw only and are marked `accessibilityElementsHidden`.

## Localisation

Every user-facing string goes through `localized(_:)`, with keys added to a new `Scripts/localization/strings/LayoutTools.json` fragment in all twelve languages, and the catalogue rebuilt with `Scripts/localization/build_catalog.py`. Measurements are formatted, not translated; any sentence embedding one is a single key with an interpolation so its word order can change with the language.

## Safety

Both tools are off inside an XCTest process and on App Store builds, through the same `AppEnvironment` checks the rest of the toolkit uses. Neither mutates the app: no frames are changed, no constraints touched, nothing is set on a host view. The ruler consumes touches only while it is active, and Layout Guides never do.

## Testing

**Pure, so tested directly:**

- `LayoutRulerGeometry` — nearest-edge selection for a point above, below, inside and diagonally off a rect; distance; the label's position when the measurement runs off an edge; the degenerate zero-length case.
- `ViewProbe` — the deepest-match rule, each skip rule (hidden, transparent, out of bounds, Scyther-owned), and that it never reads an accessibility property. That last one is worth an explicit test given the audit's history.
- `LayoutGuidesView`'s inset arithmetic as a pure function of a window's insets and margins, including the zero-inset omission.
- The settings singletons against a throwaway `UserDefaults` suite, as the other overlays are.

**Not unit-tested, and said plainly:** the drag itself, and how the overlay's touch handling coexists with the app underneath. Nothing available here can drive a drag. These are verified by hand and the verification is listed below rather than implied.

## Verification on device

Before the work is called done, on the simulator:

1. Turn on Layout Guides and confirm the safe-area lines sit where the safe area actually ends, on a device with a home indicator and one without.
2. Confirm Layout Guides stay visible and correct while scrolling and navigating the host app, and survive a rotation.
3. Activate the ruler, drag between two labels in snap mode, and confirm the reported distance matches their real gap and the readout names both views.
4. Confirm a drag over Scyther's own control does not measure the control.
5. Switch to free mode and confirm the endpoints stay where they are put.
6. Confirm Done exits, and that the shake gesture also reaches the menu while the overlay is active.
7. Rotate mid-measurement and confirm the measurement clears rather than persisting against a layout that has moved.
