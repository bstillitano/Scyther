# UI Debugging Tools

Visual aids to debug layout issues, create demos, and inspect your UI.

@Metadata {
    @PageColor(green)
}

## Overview

Scyther provides several visual debugging tools to help you identify layout issues, create app demonstrations, and understand your view hierarchy.

## Touch Visualizer

Display visual indicators for touch events - perfect for screen recordings and demos.

### Enabling Touch Visualization

```swift
// Via the interface facade
Scyther.interface.touchVisualizerEnabled = true

// Or directly
InterfaceToolkit.instance.visualiseTouches = true
```

### Configuration Options

Customize the touch indicator appearance:

```swift
var config = TouchVisualiserConfiguration()

// Show how long each touch has been active
config.showsTouchDuration = true

// Scale indicator based on touch pressure/radius
config.showsTouchRadius = true

// Log touch events to console
config.loggingEnabled = true

// Custom indicator color
config.touchIndicatorColor = .systemBlue

// Apply configuration
TouchVisualiser.instance.config = config
```

### Use Cases

- **App Demos**: Show users exactly where to tap
- **Bug Reports**: Record touch interactions for developers
- **Tutorials**: Create visual guides for your app
- **Accessibility Testing**: Verify touch targets are properly sized

## Grid Overlay

Display an alignment grid over your UI to verify spacing and alignment.

### Enabling the Grid

```swift
// Enable grid overlay
Scyther.interface.gridOverlayEnabled = true
```

### Customization

```swift
// Set grid size (spacing between lines)
GridOverlay.instance.size = 8  // 8-point grid

// Adjust opacity
GridOverlay.instance.opacity = 0.5

// Change color scheme
GridOverlay.instance.colorScheme = .blue
```

### Design System Verification

Use the grid overlay to verify your app follows your design system's spacing rules:

```swift
// For an 8-point grid system
GridOverlay.instance.size = 8

// For a 4-point grid system
GridOverlay.instance.size = 4
```

## Layout Guides

Draw the key window's safe-area insets and layout margins over your UI, each labelled with its
measurement in points.

### Enabling Layout Guides

```swift
// Enable layout guides
Scyther.interface.layoutGuidesEnabled = true
```

With no key window there is nothing to draw over, so the menu's toggle is disabled rather than
persisting a setting that puts nothing on screen — the same rule the Layout Ruler's row reports
with an alert.

### Reading the Overlay

Safe-area insets are drawn as solid blue lines; layout margins are drawn as dashed purple lines,
offset along the line from the safe-area label so the two remain legible even where a margin
lands on top of a safe-area inset — the common case, since a root view's `layoutMargins` are
inset from the safe area by default. An inset that is zero — the bottom safe area on a device
with no home indicator, say — is not drawn at all: a line labelled `0 pt` flush against the
screen edge would be noise, not information.

### Why a separate toggle

Layout Guides has its own toggle rather than living inside the Layout Ruler, even though both draw
over the same window. The guides are what you want on while *using* the app — scrolling,
navigating, watching a layout misbehave — and the ruler's overlay consumes every touch while it is
active. Tying the guides to the ruler would show them only while the app cannot be driven, which is
exactly the moment they are least useful.

## Layout Ruler

Measure between two points on the running app by dragging, with each end snapping to the nearest
edge of the view beneath it.

### Using the Ruler

Open the Scyther menu and choose **Layout Ruler** under **UI/UX**. The menu dismisses and an
overlay takes over the screen: drag anywhere to measure. The measurement stays on screen after
your finger lifts so it can be read, is replaced by the next drag, and is cleared by a tap.

The overlay consumes every touch while it is up, so the app underneath cannot be tapped, scrolled
or navigated until you leave it. Tap **Done** to exit the overlay and hand touches back to the
app — it is always visible for exactly that reason. (The shake gesture still reaches the menu
regardless, because shake is a motion event rather than a touch.)

### Snap and Free

**Snap**, the default, attaches each end of the measurement to the nearest edge of the view under
it, so a drag roughly between two labels reports the real gap between them rather than how steady
your thumb was. The readout names both ends — `UILabel.bottom → UIImageView.top` — using each
view's class and edge, which is the only name a view reliably has.

**Free** leaves both ends exactly where you put them, for measuring into whitespace or to a point
inside an image. Its readout carries the distance alone, since it attached to nothing.

An end with nothing under it falls back to the point itself and is named `free point`, rather than
reporting a snap that did not happen. Scyther's own interface is never measured: the probe skips it
and measures the app underneath, so the ruler's own control does not get in the way of what is
behind it.

### Reading the Measurement

The line, its endpoint dots, and the readout's border are all drawn in green — a colour none of
Scyther's other overlays use, so several can be on screen at once without one being mistaken for
another: the grid is red, Layout Guides are blue and purple, and the accessibility audit's overlay
is orange.

The readout itself always shows the distance in full, on its own line. The names of what it
snapped to sit on the line beneath, truncated in the middle when there isn't room for them — the
start and end of a name like `UILabel.bottom` carry more information than its middle, so that's
the part given up first.

### Why not a hit test

The ruler does not ask UIKit which view would receive a touch at a point, because that is a
different question from which view is there to measure. `hitTest(_:with:)` is steered by
`isUserInteractionEnabled` and by any view that overrides it, so it skips exactly the labels and
image views a developer is most likely to want to measure, and it has no notion of Scyther's own
interface being off-limits.

Instead the ruler walks the hierarchy itself, skipping anything hidden, fully transparent, or
Scyther's own, and preferring the deepest view that visibly paints something at the point — a
background colour, rendered layer content, a border, or a shadow — over the deepest view full
stop. That preference is not a refinement: without it the ruler cannot measure anything on iOS 26
at all, because a plain SwiftUI `TabView` installs a full-screen, unpainted container in front of
the whole app to host its floating tab bar, and a plain hit test — or a walk with no preference for
paint — returns that container for every point on the screen.

Neither activation nor the mode survives a relaunch. A ruler that came back after a restart would
be a debugging tool that has to be remembered and switched off, and it eats every touch on the
screen while it is on.

A rotation clears the measurement. Its endpoints described a layout that no longer exists. An
orientation change the app does not honour — face-up, face-down, or a rotation a portrait-locked
app ignores — leaves it alone, because nothing moved.

With no key window there is nothing to draw over, so the row says so in an alert rather than
activating and putting nothing — not even its own Done button — on screen.

## View Frame Debugging

Highlight view boundaries to understand your view hierarchy.

### Show View Frames

Toggle colored borders around all views:

```swift
InterfaceToolkit.showViewFrames = true
```

Each view gets a randomly colored border, making it easy to see view boundaries and identify overlapping or misaligned views.

### Show View Sizes

Display dimension labels on views:

```swift
InterfaceToolkit.showViewSizes = true
```

This shows width and height labels, helping you verify views are sized correctly.

## View Hierarchy

Browse a snapshot of the key window's view hierarchy — every view's class, its size, and why it
might be invisible — without adding anything to your code. Open **View Hierarchy** under **UI/UX**
in the Scyther menu.

### The Tree

The page opens on the key window's hierarchy, collapsed to the first two levels. Each row carries
the view's class name, its size in points, and a badge for **hidden**, **zero-size**, or
**off-screen** — the three states that make a view interesting and that nothing else in the
toolkit reports. A row has two separate controls: a leading chevron that expands or collapses it
(absent on a leaf), and the row itself, which pushes the view's detail page.

A `.searchable` field matches a view's class name and any text it carries itself — a `UILabel`'s
`text`, a `UIButton`'s current title — and lists each hit with its ancestor path, so a result reads
`UIWindow › … › UIButton` before you tap it.

Pull to refresh walks the window again; expansion is preserved for rows that still exist. The
header states the node count and when the snapshot was taken.

### The Detail Page

Selecting a row pushes a page carrying, in order: a rendered thumbnail beside a position map
showing where the view sits on a scaled outline of the screen; **Geometry** (`frame`, `bounds`,
`center`, safe-area insets, layout margins); **Appearance** (`alpha`, `isHidden`, background
colour, corner radius, `clipsToBounds`, content mode, and — for views that carry text — the
string, font and text colour); **Context** (the owning view controller, the view's position in the
responder chain, and whether it is first responder); and **Behaviour**
(`isUserInteractionEnabled`, `tag`).

### Read-Only, and a Snapshot Rather Than a Live Tree

The inspector never changes a frame, a flag, or a colour, and it skips Scyther's own views, so the
tree it shows is the host app's hierarchy and nothing else.

It also never updates itself on its own. Keeping the tree in step with the hierarchy needs a
change signal, and UIKit has no clean one: the alternatives are polling on a timer or swizzling
layout methods, and a full walk on every layout pass is precisely the hot-path mistake the
accessibility audit taught this project in 4.3.0 — see <doc:AccessibilityAuditing>. So the page
opens on a snapshot, states its own age in the header, and only re-walks the window when you pull
to refresh. A developer who assumes the tree tracks the running app live will misread a stale
snapshot as a bug in their own layout; it isn't one — it's an old picture, and pulling to refresh
takes a new one.

### Why `ViewNode` Holds No View

`ViewNode` is a value type with no reference to the `UIView` it describes. A tree that strongly
held views would keep an entire screen alive for as long as the inspector's page was open. The
thumbnail still needs the real view, so `ViewHierarchySnapshot` keeps a separate side table
mapping each node's identity to its view, kept **weak** — so a snapshot left open on a screen you
have since navigated away from does not keep that screen alive. A node whose view has gone
resolves to nothing, and the detail page says so rather than rendering an empty box.

### Why the Ownership Check Carries a Boundary

`ViewHierarchyWalker` skips views owned by Scyther, reusing the same
`AuditNode.isScytherOwned(below:)` rule the accessibility audit uses rather than inventing a
second answer that can drift from the first. It calls the `below:` form, passing the parent's own
identity, rather than climbing the whole responder chain from scratch for every view in the tree:
on a 1,663-node tree, re-climbing per node measured 8.73 ms against 3.01 ms with the boundary
passed through — 69% of the walk spent re-answering a question a parent had already answered. This
mirrors the fix the accessibility audit made for the same reason; the reasoning is at
`Sources/Scyther/Features/AccessibilityAudit/AuditNode.swift:220-234`.

## Slow Animations

Reduce animation speed to debug timing issues:

```swift
InterfaceToolkit.slowAnimationsEnabled = true
```

Animations run at 10% speed, making it easier to:
- Debug animation glitches
- Verify animation sequences
- Test interruptible animations
- Identify janky transitions

## Font Browser

Explore all available system fonts. Access via **Fonts** in the Scyther menu to:

- Browse all font families
- See all weights and styles
- Preview fonts at different sizes
- Copy font names for use in code

## Interface Previews

Register UI components for quick preview access:

```swift
// Register a view for preview
Scyther.register(preview: MyCustomButton.self, name: "Custom Button")
Scyther.register(preview: ProfileCard.self, name: "Profile Card")
```

Access registered previews in the Scyther menu under **Interface Previews**.

## Programmatic Access

All UI tools are accessible programmatically:

```swift
// Touch visualization
Scyther.interface.touchVisualizerEnabled = true/false

// Grid overlay
Scyther.interface.gridOverlayEnabled = true/false

// Layout guides
Scyther.interface.layoutGuidesEnabled = true/false

// View debugging
InterfaceToolkit.showViewFrames = true/false
InterfaceToolkit.showViewSizes = true/false
InterfaceToolkit.slowAnimationsEnabled = true/false
```

## Best Practices

### 1. Use for Screenshots

Enable the grid overlay when taking design review screenshots to verify alignment.

### 2. Demo Recordings

Enable touch visualization before recording app demos or tutorials.

### 3. Layout Debugging Workflow

When debugging layout issues:
1. Enable **Show View Frames** to see boundaries
2. Enable **Show View Sizes** to verify dimensions
3. Enable **Grid Overlay** to check alignment
4. Use **Slow Animations** if the issue involves animation

### 4. Disable in Production

All UI debugging tools are automatically disabled in App Store builds.

## See Also

- ``InterfaceToolkit``
- ``TouchVisualiser``
- ``TouchVisualiserConfiguration``
- ``GridOverlay``
- <doc:UIDebuggingTools#Layout-Guides>
- <doc:UIDebuggingTools#Layout-Ruler>
- <doc:UIDebuggingTools#View-Hierarchy>

