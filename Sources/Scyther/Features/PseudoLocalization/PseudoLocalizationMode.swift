//
//  PseudoLocalizationMode.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation

/// The pseudo-localisation behaviours currently switched on, as one value.
///
/// Modelled as an `OptionSet` rather than a handful of loose `Bool`s because every consumer cares
/// about the *combination*: ``PseudoLocalizationTransform`` needs to know the order to apply them in,
/// ``PseudoLocalization`` needs to know whether *any* text mode is on before it installs a hook
/// into the host app, and ``localized(_:comment:override:)`` needs a single cheap emptiness check
/// on the hot path where every string in Scyther's UI is resolved.
///
/// It is `Sendable` because the transform runs wherever a string happens to be resolved — a
/// background queue formatting a network log label as readily as the main actor drawing a row.
///
/// ## Topics
///
/// ### Modes
/// - ``accented``
/// - ``lengthened``
/// - ``rightToLeft``
/// - ``showsKeys``
///
/// ### Presentation
/// - ``showsBoundaries``
///
/// ### Grouping
/// - ``textAffecting``
struct PseudoLocalizationMode: OptionSet, Sendable, Hashable {
    /// The raw bit field, as required by `OptionSet`.
    let rawValue: Int

    /// Creates a mode set from its raw bit field.
    ///
    /// - Parameter rawValue: The bit field.
    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Replaces Latin letters with accented look-alikes, so `Hello` reads `Ĥéļļö`.
    ///
    /// The point is not the accents themselves but what stays *unaccented*: any text still
    /// rendering as plain ASCII never went through a localisation lookup at all, which is the
    /// single most common reason a screen ships untranslated.
    static let accented = PseudoLocalizationMode(rawValue: 1 << 0)

    /// Pads text to roughly 135% of its length, the expansion German and Finnish typically bring.
    ///
    /// Layouts are usually sized against English, the shortest major language. Growing every
    /// string surfaces the labels that clip, the buttons that truncate, and the stacks that wrap
    /// to a second line, before a translator's work does.
    static let lengthened = PseudoLocalizationMode(rawValue: 1 << 1)

    /// Forces right-to-left layout without switching to an RTL language.
    ///
    /// Catches hard-coded leading/trailing assumptions — a chevron pinned with `.trailing` that
    /// was really meant as "the far edge", a manual `frame(x:)`, an image that should have been
    /// mirrored. Unlike the other three this changes no text at all, so it is deliberately not
    /// part of ``textAffecting``.
    ///
    /// Its reach is also unlike the other three, and narrower than it first appears: it mirrors
    /// **Scyther's own interface only**, immediately, in both directions, and does not affect the
    /// host app at all. ``PseudoLocalizationLayout`` explains why reaching further was tried and
    /// deleted, and what a developer should use instead.
    static let rightToLeft = PseudoLocalizationMode(rawValue: 1 << 2)

    /// Renders the catalog key in place of its translation.
    ///
    /// Answers the question the other modes cannot: *which* key produced this label. It is the
    /// fastest way to find the entry to edit for a piece of copy someone has queried, and the
    /// fastest way to spot a key that resolved to the wrong entry entirely.
    static let showsKeys = PseudoLocalizationMode(rawValue: 1 << 3)

    /// Keeps the `[` and `]` that mark where a transformed string starts and ends.
    ///
    /// The odd one out, and deliberately so: it transforms nothing by itself and switches nothing
    /// on. It is a setting *about* the other modes — the only delimiters pseudo-localisation
    /// produces are the ones ``lengthened`` puts around a padded string, and this decides whether
    /// they are drawn. With no text mode on it therefore does nothing at all, which
    /// ``PseudoLocalizationTransform/apply(to:key:modes:)`` gets for free from the guard it
    /// already had.
    ///
    /// Not part of ``textAffecting`` for the same reason ``rightToLeft`` is not: that set decides
    /// whether the hook into the host app's string loading is worth installing, and a mode that
    /// only changes how another mode renders must never install it on its own.
    ///
    /// It is also the one mode that is on unless a developer has turned it off. The brackets are
    /// the diagnostic rather than decoration — the padding dots say a string grew, but only the
    /// closing bracket says whether the end of it was cut off — so the default keeps them and the
    /// switch exists for the developer who has seen enough of them.
    static let showsBoundaries = PseudoLocalizationMode(rawValue: 1 << 4)

    /// The modes that change the characters of a string, as opposed to the direction it is laid
    /// out in.
    ///
    /// The distinction is load-bearing: the hook into the host app's string loading is worth
    /// installing only when one of these is on, and neither ``PseudoLocalizationMode/rightToLeft``
    /// nor ``PseudoLocalizationMode/showsBoundaries`` alone must install it — the first changes a
    /// layout attribute rather than a string, and the second only decides how one of these three
    /// renders.
    static let textAffecting: PseudoLocalizationMode = [.accented, .lengthened, .showsKeys]
}
