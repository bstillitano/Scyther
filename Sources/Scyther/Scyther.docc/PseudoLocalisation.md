# Pseudo-localisation

Find out whether an interface survives translation, before a single string is translated.

@Metadata {
    @PageColor(green)
}

## Overview

Most localisation bugs are not translation bugs. They are layout bugs that only appear once the
copy changes: a label sized against English that clips at 130%, a chevron pinned to the trailing
edge that ends up on the wrong side in Arabic, a string somebody forgot to put through
`NSLocalizedString` at all. All three are findable long before a translator is briefed, by
rendering the app with copy that *behaves* like a translation without *being* one.

**UI/UX → Pseudo-localisation** offers four modes, each a switch, each off by default, and all
freely combinable:

| Mode | What it does | What it finds |
| --- | --- | --- |
| Accented | `Hello` becomes `Ĥéļļö` | Text still in plain ASCII was never localised |
| Lengthened | `[Hello··]`, about 135% of the original | Clipping and truncation |
| Right to Left | Forces RTL layout | Hard-coded leading/trailing assumptions |
| Show Keys | Renders `Selected %lld items` instead of `Selected 5 items` | Which catalog entry produced a piece of copy |

The bracketing in Lengthened is the point of it: a label that has lost its closing `]` was
truncated, which is far easier to see in a screenshot than judging whether some accented text
looks a few characters short.

## What it can reach, and what it cannot

This is the part worth reading before relying on the feature.

Scyther's own interface is always transformed. Every string in the package goes through
``localized(_:comment:)``, so the transform sits directly in the resolution path and nothing can
slip past it.

Your app is a different question, and the answer depends on how your code loads its strings:

- **`NSLocalizedString` is reached.** It is a thin wrapper over
  `-[NSBundle localizedStringForKey:value:table:]`, an Objective-C method, and Scyther swizzles it
  while a text mode is on. That covers UIKit apps, storyboard and XIB strings, and any Swift code
  written the traditional way.
- **`String(localized:)` is not reached.** Neither is `LocalizedStringResource`, and neither is
  SwiftUI's `Text("Some key")`.

The second point was measured rather than assumed. With that `NSBundle` method hooked, resolving a
string through each of those paths — including rendering a `Text` all the way to a bitmap with
`ImageRenderer`, which succeeded — never once reached the hook. Foundation's Swift-native
localisation path does not descend into `NSBundle` at all, and no other selector on the class sees
those calls either, the private `localizedStringForKey:value:table:localizations:` included. There
is no hookable funnel for them.

So, plainly: **on a modern SwiftUI app whose copy is written as `Text("…")`, the three text modes
pseudo-localise Scyther's own interface and nothing else.** That still shows what
pseudo-localisation looks like, and Scyther's menu is a real, fully localised SwiftUI app to look
at it on — but it is a demonstration, not a test of your screens. On a UIKit or
`NSLocalizedString`-based app it is a test of your screens.

Right to Left has no such limit. It is a UIKit semantic attribute, not a string lookup, so it
applies to the host app regardless of how its copy is loaded.

## Safety

The rule behind all of this: **never produce broken text that is not a localisation problem.** A
dead link or a plural that stops expanding is not a finding, it is a defect the developer will
spend an afternoon chasing in their own code, and a diagnostic tool that manufactures those is
worse than no tool.

- Every mode is off by default and persisted under `Scyther_pseudo_localization_*` in
  `UserDefaults.scyther`.
- The swizzle is installed only while a text mode is on, and removed the moment the last one is
  switched off. An app that never opens the page never has its string loading touched.
- Only `Bundle.main` is transformed, and within it only the default `Localizable` table. UIKit's
  own "Cancel" and "Done" resolve normally, and so does a table the app named on purpose — teams
  routinely keep analytics identifiers, feature-flag names and segment keys in one. The trade is
  one-directional and deliberate: copy in a named table is missed, which costs coverage, whereas
  transforming an identifier table would change what the app *does*.
- `.stringsdict` plurals are returned untouched, as the exact object Foundation produced. See
  ``PseudoLocalizationTransform/carriesPluralConfiguration(_:)`` for why neither the variable name
  nor the attached configuration can be carried through a transform.
- Accenting preserves everything that is not copy: format specifiers, `.stringsdict` variables,
  brace placeholders, and URLs and email addresses. See
  ``PseudoLocalizationTransform/accentuate(_:)``.
- Neither the swizzle nor the forced layout direction is installed on an App Store build or under
  XCTest. Each carries that guard itself rather than relying on its caller, and an App Store build
  honours no persisted mode at all.

## The escape hatch

Pseudo-localising a debug menu has an obvious trap: with Show Keys and Right to Left both on, the
switch that undoes it would be a raw catalog key laid out backwards, somewhere in a list of raw
catalog keys laid out backwards.

The Pseudo-localisation page, and its row in the menu, are therefore the one part of Scyther whose
*text* is never transformed — they resolve their copy through `localizedChrome(_:comment:)`
instead. The page carries a **Sample** row so it can still show what the modes do while remaining
the one place they do not apply, and a **Turn Everything Off** button.

The exemption covers text only. Right to Left is a process-wide UIKit attribute, so this page flips
along with everything else; that is deliberate, because the text stays perfectly legible mirrored
and insulating one screen from the layout mode would misrepresent what the mode does.

The exemption is deliberately narrow. Exempting the whole menu would be safer still and would also
mean there was nothing to see.

## Known limits

- A screen that has already laid itself out does not always re-resolve its constraints when the
  layout direction changes, so flipping Right to Left on a visible screen can leave it
  half-flipped. Relaunching settles it: the persisted switch is re-applied before any of the app's
  own views exist.
- Strings the app has already resolved and cached are not revisited. A label rendered before the
  mode was switched on keeps its old text until something re-renders it.
- Show Keys recovers the catalog key by reflecting on `String.LocalizationValue`, whose layout is
  not a contract. If a future OS changes it, the mode falls back to showing the resolved English
  copy rather than failing.
- Pseudo-localised menu titles do not match what you type into the menu's search field, for the
  same reason a French menu does not match English queries. The search route back to this page
  survives on its hand-written ASCII keyword aliases, which a test pins.
- Copy kept in a named `.strings` table, and any `.stringsdict` plural, are not transformed.
- URLs, email addresses and brace placeholders are recognised by shape, not parsed. A token that
  merely looks like one is left alone; the bias is deliberately towards under-transforming, since
  a missed string costs coverage and a mangled link costs the developer an afternoon.

## Topics

### Settings

- ``PseudoLocalization``
- ``PseudoLocalizationMode``

### Transformation

- ``PseudoLocalizationTransform``
- ``PseudoLocalizationKey``

### Hooks

- ``PseudoLocalizationHostHook``
- ``PseudoLocalizationLayout``

### Interface

- ``PseudoLocalizationView``
- ``PseudoLocalizationViewModel``
