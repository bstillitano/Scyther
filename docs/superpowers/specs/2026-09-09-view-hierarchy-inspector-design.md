# View Hierarchy Inspector — Design

**Date:** 2026-09-09
**Status:** Approved

## Goal

Answer one question the app cannot currently be asked: **what is this view, and what state is it in?**

A browsable snapshot of the key window's view hierarchy, reachable from the Scyther menu, where
selecting a view shows what it is, where it sits, how it looks, and which controller owns it.

It exists because the tools shipped in 4.7.0 stop short of it. The layout ruler measures a gap; it
cannot tell you that the view making the gap is hidden, or zero-height, or belongs to a controller
you thought you had popped.

## Non-Goals

Each of these is a feature in its own right, and none is needed to make this useful:

- **Auto Layout constraints.** Deliberately excluded. Constraint descriptions are gnarly, and this
  app is SwiftUI-backed — the constraint list reads empty on exactly the screens it would be
  consulted from. "Why is this gap 23 points" stays unanswered by this tool.
- **Editing anything.** The inspector reports. It never changes a frame, a flag, or a colour.
- **A live highlight on the running app.** See Decisions.
- **Other windows.** The key window only.
- **Continuous tracking.** The tree is a snapshot, not a live view of the hierarchy.
- **Tap-to-inspect.** Considered and rejected in favour of the tree; see Decisions.

## Decisions taken

Settled with the owner before this document was written. Each is here because it shapes the rest.

1. **A tree browser, not tap-to-inspect.** Tap-to-inspect can only reach what is visible, and the
   views worth inspecting are frequently the ones that are not: hidden, zero-size, or behind
   something else. The tree reaches them; that is the whole reason for choosing it.
2. **Geometry, appearance and responder context — not constraints.** Where a view is, how it looks,
   and which controller and responder chain it belongs to. Adding constraints was considered and
   dropped: substantially more work, paying off on UIKit screens and reading empty on SwiftUI ones.
3. **A full-screen page, with a thumbnail rather than a live highlight.** A half-height sheet with
   the app live above it was designed and rejected, along with a dismiss-to-highlight variant. Both
   give a highlight that only works for views already visible on screen — so on exactly the cases
   that motivated choosing a tree, the highlight silently draws nothing, and an empty outline reads
   as "no such view" rather than "not currently on screen". A rendered thumbnail plus a position
   drawn on a scaled screen outline works identically whether the view is on screen, off screen, or
   hidden.

   This also makes the page a normal Scyther page — the same shape as Network Logs — with no new
   presentation machinery, and it dissolves a problem rather than solving it: with the menu
   full-screen the host app is not being driven underneath, so the snapshot cannot go stale while
   it is being read.
4. **Search, with the tree collapsed by default.** A heuristic that folded framework scaffolding
   into its nearest meaningful ancestor was considered and dropped. The rule is a judgement call,
   and the view you want is occasionally the one it hides.

## The tree

The page opens on a snapshot of the key window, collapsed to the first two levels.

Each row carries the view's class name, its size in points, and a badge when the view is
**hidden**, **zero-size**, or **off-screen** — the three states that make a view interesting and
that nothing else in the toolkit reports. Precisely: *hidden* is `isHidden` or an effective alpha
at or below 0.01 anywhere in its ancestry; *zero-size* is a width or height of zero; *off-screen*
is a frame, converted to window space, that does not intersect the window's bounds.

A `.searchable` field matches a view's class name and any text the view itself carries — a
`UILabel`'s `text`, a `UIButton`'s current title. Results are listed as matches with the ancestor
path to each, so a hit reads `UIWindow › … › UIButton` and you can see where it lives before
tapping it. Selecting a result opens that view's detail.

Pull to refresh walks the window again. The header states how old the snapshot is, because a
snapshot that does not say it is a snapshot is a lie.

### Why a snapshot rather than a live tree

Keeping the tree in step with the hierarchy needs a change signal, and UIKit has no clean one:
the options are polling on a timer or swizzling layout methods, and a full walk on every layout
pass is precisely the hot-path mistake the accessibility audit taught this project in 4.3.0. The
page is full-screen, so nothing is driving the app while the tree is open; the snapshot is accurate
for as long as it is being read.

## The detail

Selecting a view pushes a page carrying, in this order:

**Where it is.** A rendered thumbnail of the view beside its position drawn on a scaled outline of
the screen. A hidden or zero-size view has nothing to render, and the page says so — "nothing to
show, this view is hidden" — rather than presenting an empty box as though it were the answer.

**Geometry.** `frame`, `bounds`, `center`, safe-area insets, layout margins.

**Appearance.** `alpha`, `isHidden`, `backgroundColor`, `layer.cornerRadius`, `clipsToBounds`,
`contentMode`, and for views that carry text, the string, font and text colour.

**Context.** The owning view controller, found by walking the responder chain from the view; the
view's position in that chain; and whether it is first responder. This is often the fastest answer
to "which screen is this actually from" in a deep navigation stack.

**Behaviour.** `isUserInteractionEnabled`, `tag`.

## Architecture

`Sources/Scyther/Features/ViewHierarchy/`:

| File | Responsibility |
| --- | --- |
| `ViewNode.swift` | **Pure, `Sendable`.** One snapshot node: identity, class name, frame in window space, the hidden/zero-size/off-screen flags, its own text, and children. Holds no `UIView`. |
| `ViewHierarchyWalker.swift` | `@MainActor`. Builds the snapshot from the key window. |
| `ViewNodeSearch.swift` | **Pure.** A query and a snapshot in; matches with their ancestor paths out. |
| `ViewThumbnailRenderer.swift` | `@MainActor`. Renders one view on demand, size-capped. |
| `ViewHierarchyView.swift` / `ViewHierarchyViewModel.swift` | The page: `List` with `DisclosureGroup`, `.searchable`, `.refreshable`. |
| `ViewDetailView.swift` / `ViewDetailViewModel.swift` | The detail page. |

`MenuItem` gains `.viewHierarchy`, in the UI/UX section, as a navigation row. Adding a `MenuItem`
case forces edits the file list does not imply — `MenuSection`, `MenuView`'s row builder and its
search-result builder, `MenuSearchIndex`, and a hard-coded count assertion in `MenuItemTests` —
and a missing case in `MenuView.searchResultRow(for:)` produces a search hit that pushes a blank
page, which is a defect this project has already shipped once.

### The snapshot holds no views

`ViewNode` is a value type with no reference to the `UIView` it describes. A tree that strongly
held views would keep an entire screen alive for as long as the page was open.

The thumbnail still needs the real view, so a separate `@MainActor` side table maps node identity
to a **weak** `UIView`. A node whose view has gone renders as unavailable rather than as a blank
thumbnail — the same honesty rule as the hidden case.

### The walk must stay cheap

The accessibility audit hung the app in 4.3.0 by asking every view for its accessibility children,
because doing so forces `UIAccessibility` to compute a subtree recursively. The walker reads
`subviews`, `frame`, `isHidden` and `alpha` — stored properties — and **must never touch the
accessibility tree**. Text is read from concrete types (`UILabel.text`, `UIButton.currentTitle`),
never from an accessibility property.

The walk skips views owned by Scyther, reusing ``ScytherPresentedUI`` and the ownership test the
accessibility audit and `ViewProbe` already share, rather than inventing a second answer that can
drift from the first.

### Rasterisation is the one expensive thing here

Rendering a view is rasterisation, and it is on the same list of costs as the audit's mistake. It
happens for the **selected view only**, never per row and never eagerly for the tree, and does not
wait for screen updates. It is capped at 512 × 512 points: a larger view is rendered scaled to fit
that box, preserving its aspect ratio, so a full-screen view costs the same as a button.

## Edge cases

| Case | Behaviour |
| --- | --- |
| No key window | The menu row reports it rather than appearing to work. |
| A view's `UIView` has been deallocated since the snapshot | The row shows as unavailable; the detail says so instead of rendering. |
| Hidden or zero-size view | No thumbnail; the page says which of the two it is. The position map still draws the frame. |
| View entirely off-screen | Thumbnail renders normally; the position map draws the frame outside the screen outline so the offset is visible. |
| Very deep hierarchy | Visual indentation stops increasing after eight levels, so a deep node keeps its label readable on a phone; the row still carries its true depth, and the ancestor path in search shows the full chain. |
| Search matches nothing | An empty state naming the query, not a blank list. |
| Rotation while the page is open | The snapshot is unchanged and stays honest — its header already says when it was taken. Pull to refresh for the new layout. |

## Accessibility

The tree and the detail are ordinary SwiftUI lists and read correctly with VoiceOver. Each row's
label is its class name plus its badges, so "hidden" and "zero-size" are spoken rather than being
carried only by a visual badge. The thumbnail is decorative and hidden from VoiceOver; the position
map is not a substitute for the geometry values, which are text on the same page.

## Localisation

Every user-facing string goes through `localized(_:)`, with keys added to a new
`Scripts/localization/strings/ViewHierarchy.json` fragment in all twelve languages, and the
catalogue rebuilt with `Scripts/localization/build_catalog.py`. Class names, property names and
measurements are not translated. Any sentence embedding a value is a single key with an
interpolation, so its word order can change with the language — never a key built by string
interpolation, which cannot resolve.

## Safety

Off inside an XCTest process and on App Store builds, through the same `AppEnvironment` checks the
rest of the toolkit uses. Nothing is mutated: no frames, no flags, no constraints, nothing set on a
host view. The inspector does not consume touches — it is a page, not an overlay.

## Testing

**Pure, so tested directly:**

- `ViewNodeSearch` — matching on class name and on carried text; the ancestor path for a deep hit;
  a query matching nothing; case and diacritic insensitivity, matching the toolkit's other
  searchable pages.
- `ViewHierarchyWalker` against a synthetic hierarchy — the shape of the tree, the hidden,
  zero-size and off-screen flags, that a Scyther-owned subtree is skipped, and that no accessibility
  property is read. That last one is worth an explicit test given the audit's history.
- The position map's arithmetic — a frame scaled into the screen outline, including a frame that
  falls outside it.
- Indentation capping — that depth nine indents no further than depth eight, and that the node's
  reported depth is unaffected.

**Not unit-tested, and said plainly:** thumbnail fidelity, and how the page behaves against a real
app's hierarchy. Nothing available here can assert what a rasterised view looks like. These are
verified by hand, and the verification is listed below rather than implied.

## Verification on device

Before the work is called done, on the simulator:

1. Open the page on the example app and confirm the tree matches the screen behind it — the tab
   bar, the list, and the section cards all present and nested correctly.
2. Search for text that appears in a label and confirm the match, its ancestor path, and that
   selecting it opens the right view.
3. Select a plain visible view and confirm the thumbnail looks like the view and the position map
   puts it where it actually is.
4. Select a hidden view and confirm the page says it is hidden rather than showing an empty box.
5. Confirm no Scyther view appears anywhere in the tree.
6. Navigate the host app, reopen the page, and confirm the new snapshot reflects the new screen.
7. Open the page on a screen with a long list and confirm scrolling the tree stays smooth — the
   walk is a snapshot, so no rasterisation should occur while scrolling.
