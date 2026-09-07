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
freely combinable — plus a fifth switch that is a setting about them rather than a mode of its own:

| Mode | What it does | What it finds |
| --- | --- | --- |
| Accented | `Hello` becomes `Ĥéļļö` | Text still in plain ASCII was never localised |
| Lengthened | `[Hello··]`, about 135% of the original | Clipping and truncation |
| Right to Left | Mirrors the layout | Hard-coded leading/trailing assumptions |
| Show Keys | Renders `Selected %lld items` instead of `Selected 5 items` | Which catalog entry produced a piece of copy |

The bracketing in Lengthened is the point of it: a label that has lost its closing `]` was
truncated, which is far easier to see in a screenshot than judging whether some accented text
looks a few characters short.

That is also why **Show Boundaries** — the fifth switch, and the only one that ships **on** —
exists at all. The padding dots say a string grew; only the closing bracket says whether the end of
it was cut off. Switching it off keeps the expansion and drops the delimiters, giving their two
characters back to the padding so both forms grow a string by the same amount. It transforms
nothing itself, so with every text mode off it does nothing whichever way it is set, and it reads
as on when nothing has been stored for it — an install that predates it keeps the brackets it has
always had. See ``PseudoLocalizationMode/showsBoundaries``.

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

Right to Left is a different mechanism, and it has a different limit rather than none. It changes
no text, so it does not care how your copy is loaded — but a layout direction cannot simply be
forced onto views that already exist. What flips, and when:

| Surface | When it mirrors | Checked on a simulator |
| --- | --- | --- |
| The Pseudo-localisation page | Immediately | yes |
| The rest of the Scyther menu, and every page reached from it | Immediately | yes |
| The host app's UIKit views created after the switch | On navigating to them | no |
| The host app's UIKit views generally | On the next launch | no |
| **The host app's SwiftUI views** | **Never** | yes — confirmed not to |

The third column is there because this mode's reach has now been claimed wrongly three times on the
strength of how the mechanism *ought* to behave. The rows marked "no" rest on documented
appearance-proxy behaviour and have not been observed here: the example app is SwiftUI, so there is
no UIKit host in this repository to look at.

Switching the mode off needed a fix of its own, because the appearance proxy cannot undo itself: it
stamps its value onto each view as the view joins a window and never revisits it, so putting the
proxy back changes nothing that already exists, and the first version of this mode left the menu
mirrored for the rest of the session. ``PseudoLocalizationLayout/clearForcedDirection(in:)`` takes
that stamp back off Scyther's own UIKit chrome — the container its menu is presented in, and its
overlays — and writes nothing else, in that direction only. What SwiftUI hosts is deliberately out
of its reach: mirroring Scyther's interface, both ways, is the environment value ``MenuView`` and
``PseudoLocalizationView`` install, and forcing the UIKit attribute onto a hosting view as well
makes it mirror the text it *renders* — measured on a device as a menu whose every label read
backwards. Nothing above changes for the host app: its UIKit views un-mirror on the next launch
exactly as they mirror on one.

The reason for the split is ``PseudoLocalizationLayout``'s two halves. SwiftUI reads
`\.layoutDirection` from **its own** environment, which the host app owns; `UIView.appearance()`
governs UIKit views created after it changes and does not seed that environment at any point.
Scyther's interface mirrors instantly because Scyther installs that environment value itself, in
``MenuView`` and ``PseudoLocalizationView``, and can therefore change it — which is also why the
first version of this mode appeared to do nothing at all: ``MenuView`` was pinning the direction to
the language and overruling the appearance proxy every time. Being early does not rescue the host
app either; a relaunch mirrors its UIKit views and leaves its SwiftUI views exactly as they were.

There is a route to a SwiftUI host app, described in ``PseudoLocalizationLayout`` and deliberately
not taken — Xcode's own scheme option does the same job properly, without Scyther writing an
undocumented key into the host's defaults.

The toggle's own subtitle carries all of this, not just these docs. A developer looking at a switch
that says "forces right-to-left layout" and seeing nothing move has been told something false, and
no amount of accurate prose elsewhere repairs that.

## Safety

The rule behind all of this: **never produce broken text that is not a localisation problem.** A
dead link or a plural that stops expanding is not a finding, it is a defect the developer will
spend an afternoon chasing in their own code, and a diagnostic tool that manufactures those is
worse than no tool.

- Every mode is off by default and persisted under `Scyther_pseudo_localization_*` in
  `UserDefaults.scyther`. ``PseudoLocalization/showsBoundaries`` is the one switch that reads as on
  with nothing stored, and ``PseudoLocalization/reset()`` restores it to on rather than clearing
  it, because that is its shipped state.
- Show Boundaries changes how another mode renders and nothing else. It is deliberately absent from
  ``PseudoLocalizationMode/textAffecting``, so it can never install the hook into the host app's
  string loading on its own.
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

- Right to Left never reaches the host app's SwiftUI views, and reaches its UIKit views only as
  they are recreated or after a relaunch. Scyther's own interface is the only surface it mirrors
  immediately. See the table above; the toggle says so too. For a SwiftUI app, Xcode's **Edit
  Scheme → Run → Options → App Language → Right to Left Pseudolanguage** is the tool that works.
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
