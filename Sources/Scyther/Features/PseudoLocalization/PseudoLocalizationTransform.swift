//
//  PseudoLocalizationTransform.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation

/// Turns a resolved string into its pseudo-localised form.
///
/// Deliberately a pure, `static` namespace with no state, no actor and no storage. Every hook that
/// pseudo-localisation installs — Scyther's own ``localized(_:comment:override:)`` and the optional
/// hook into the host app's `NSLocalizedString` — funnels into ``apply(to:key:modes:)``, so the
/// rules live in exactly one place and can be tested without a window, a bundle or a simulator.
///
/// ## Topics
///
/// ### Applying
/// - ``apply(to:key:modes:)``
///
/// ### Individual transformations
/// - ``accentuate(_:)``
/// - ``lengthen(_:)``
///
/// ### Tuning
/// - ``expansionFactor``
/// - ``paddingCharacter``
/// - ``openingDelimiter``
/// - ``closingDelimiter``
enum PseudoLocalizationTransform {
    // MARK: - Tuning

    /// How much longer a lengthened string is made, as a multiple of the original.
    ///
    /// 1.35 sits in the middle of the 130–140% band that German and Finnish translations of
    /// English UI copy typically land in, which is the expansion a layout has to survive. Going
    /// higher would find more clipping but would also cry wolf: a layout that survives 200% is
    /// not a layout anyone ships.
    static let expansionFactor: Double = 1.35

    /// The character the padding run is built from.
    ///
    /// A middle dot rather than a space or a letter: spaces collapse in some text renderers and
    /// would make the padding invisible in exactly the truncation case being hunted, while letters
    /// read as real words and make it hard to tell padding from copy at a glance.
    static let paddingCharacter: Character = "·"

    /// Marks the start of a lengthened string.
    static let openingDelimiter: Character = "["

    /// Marks the end of a lengthened string.
    ///
    /// The delimiters are the actual diagnostic: a missing closing bracket means the label was
    /// truncated, which is far easier to spot in a screenshot than judging whether some accented
    /// text looks a few characters short.
    static let closingDelimiter: Character = "]"

    // MARK: - Applying

    /// Applies every switched-on mode to one resolved string.
    ///
    /// The ordering is not arbitrary:
    ///
    /// - ``PseudoLocalizationMode/showsKeys`` short-circuits the other two. A key rendered as
    ///   `[Ğŕîð Öṽéŕļåý··]` is not a key anyone can read back into their catalog, and reading it
    ///   back is the entire reason the mode exists. Combining it with the others is therefore
    ///   answered by precedence rather than by refusing the combination in the UI, which would
    ///   mean disabling toggles and leaving the developer to guess why.
    /// - Accenting runs before lengthening so the padding and the delimiters stay plain ASCII.
    ///   They are structural markers, not copy, and an accented `[` would be one more thing to
    ///   read past.
    /// - ``PseudoLocalizationMode/rightToLeft`` is ignored here entirely: it is a layout
    ///   attribute applied by ``PseudoLocalizationLayout``, not a property of any string.
    ///
    /// - Parameters:
    ///   - value: The already-resolved, already-formatted string.
    ///   - key: The catalog key `value` came from, used only by
    ///     ``PseudoLocalizationMode/showsKeys``.
    ///   - modes: The modes currently switched on.
    /// - Returns: The transformed string, or `value` unchanged when no text-affecting mode is on.
    static func apply(to value: String, key: String, modes: PseudoLocalizationMode) -> String {
        guard !modes.intersection(.textAffecting).isEmpty else { return value }
        if modes.contains(.showsKeys) { return key }

        var result = value
        if modes.contains(.accented) { result = accentuate(result) }
        if modes.contains(.lengthened) { result = lengthen(result) }
        return result
    }

    // MARK: - Accenting

    /// Replaces Latin letters with accented look-alikes, leaving format specifiers intact.
    ///
    /// Format specifiers have to be skipped because this transform does not always run after
    /// formatting. Scyther's own ``localized(_:comment:override:)`` hands over a string whose
    /// arguments are already substituted, but the host-app hook sits at
    /// `Bundle.localizedString(forKey:value:table:)` — which returns the *format*, for the caller
    /// to feed to `String(format:)` afterwards. Accenting the `d` of `%lld` there would turn a
    /// working format into a literal `%ļļð`, so what the developer would see is not a layout
    /// problem but a bug Scyther invented.
    ///
    /// - Parameter value: The string to accent.
    /// - Returns: `value` with every mapped letter replaced and every specifier preserved.
    static func accentuate(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "%", let end = specifierEnd(in: value, from: index) {
                result.append(contentsOf: value[index..<end])
                index = end
                continue
            }
            result.append(accentMap[value[index]] ?? value[index])
            index = value.index(after: index)
        }
        return result
    }

    /// The end index of the printf-style specifier starting at `start`, or `nil` if there is none.
    ///
    /// Hand-rolled rather than done with `NSRegularExpression` because this runs once per
    /// character of every string Scyther resolves; bridging to `NSString` and matching a pattern
    /// on the hot path of the whole UI's text is a cost the feature does not need to pay.
    ///
    /// Recognises the shape iOS catalogs actually emit: `%`, optional positional argument
    /// (`1$`), optional flags, width, precision and length modifier, then the conversion letter.
    /// `%%` is recognised too, so a literal percent is never mistaken for the start of a
    /// specifier and its trailing text left unaccented.
    ///
    /// - Parameters:
    ///   - value: The string being scanned.
    ///   - start: The index of the `%`.
    /// - Returns: The index just past the specifier, or `nil` when `start` is a bare `%`.
    private static func specifierEnd(in value: String, from start: String.Index) -> String.Index? {
        var index = value.index(after: start)
        guard index < value.endIndex else { return nil }
        if value[index] == "%" { return value.index(after: index) }

        /// Positional argument, e.g. the `1$` of `%1$@`.
        var lookahead = index
        var digits = false
        while lookahead < value.endIndex, value[lookahead].isNumber {
            lookahead = value.index(after: lookahead)
            digits = true
        }
        if digits, lookahead < value.endIndex, value[lookahead] == "$" {
            index = value.index(after: lookahead)
        }

        /// Flags, then width, then precision.
        ///
        /// The space flag is deliberately not recognised, even though printf defines it. `% o` is
        /// a legal space-flagged octal specifier and also the first three characters of "50% off";
        /// in UI copy the second reading is right essentially every time, and treating it as a
        /// specifier would leave the rest of the sentence unaccented and looking un-localised.
        while index < value.endIndex, "-+#0".contains(value[index]) {
            index = value.index(after: index)
        }
        while index < value.endIndex, value[index].isNumber {
            index = value.index(after: index)
        }
        if index < value.endIndex, value[index] == "." {
            index = value.index(after: index)
            while index < value.endIndex, value[index].isNumber {
                index = value.index(after: index)
            }
        }

        /// Length modifier, longest first so `ll` is not read as a single `l`.
        for modifier in ["hh", "ll", "h", "l", "q", "z", "t", "j", "L"] {
            if value[index...].hasPrefix(modifier) {
                index = value.index(index, offsetBy: modifier.count)
                break
            }
        }

        guard index < value.endIndex, conversionCharacters.contains(value[index]) else { return nil }
        return value.index(after: index)
    }

    /// The conversion letters that terminate a printf-style specifier.
    private static let conversionCharacters: Set<Character> = Set("@dioux XeEfgGaAcCsSpn")

    /// Latin letters mapped to visually similar accented forms.
    ///
    /// Chosen so the original word stays legible — the developer still has to *read* the screen
    /// to review it — while no character survives as plain ASCII. A map that changed only vowels,
    /// as some pseudo-localisers do, would leave `SMS` and `OK` looking untranslated when they
    /// had in fact been translated perfectly well.
    private static let accentMap: [Character: Character] = [
        "a": "å", "b": "ƀ", "c": "ç", "d": "ð", "e": "é", "f": "ƒ", "g": "ğ", "h": "ĥ",
        "i": "î", "j": "ĵ", "k": "ķ", "l": "ļ", "m": "ɱ", "n": "ñ", "o": "ö", "p": "þ",
        "q": "ǫ", "r": "ŕ", "s": "š", "t": "ţ", "u": "û", "v": "ṽ", "w": "ŵ", "x": "ẋ",
        "y": "ý", "z": "ž",
        "A": "Å", "B": "Ɓ", "C": "Ç", "D": "Ð", "E": "É", "F": "Ƒ", "G": "Ğ", "H": "Ĥ",
        "I": "Î", "J": "Ĵ", "K": "Ķ", "L": "Ļ", "M": "Ṁ", "N": "Ñ", "O": "Ö", "P": "Þ",
        "Q": "Ǫ", "R": "Ŕ", "S": "Š", "T": "Ţ", "U": "Û", "V": "Ṽ", "W": "Ŵ", "X": "Ẋ",
        "Y": "Ý", "Z": "Ž",
    ]

    // MARK: - Lengthening

    /// Pads a string to roughly ``expansionFactor`` of its length, bracketed at both ends.
    ///
    /// The brackets are counted towards the target rather than added on top of it, so the result
    /// really is about 135% and not 135% plus two. They cost the padding two characters, which
    /// matters only for strings so short that the brackets alone already overshoot — a
    /// three-character label becomes five, or 167%. That overshoot is left in deliberately: a
    /// bracket that fits is worth more than an exact ratio, because it is the bracket, not the
    /// length, that tells the developer whether the label was clipped.
    ///
    /// An empty string is returned untouched. Bracketing nothing would turn every blank
    /// accessibility value and every empty placeholder into a visible `[]`, which reads as a
    /// rendering bug rather than as a measurement.
    ///
    /// - Parameter value: The string to pad.
    /// - Returns: The padded, bracketed string.
    static func lengthen(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let target = Int((Double(value.count) * expansionFactor).rounded())
        let padding = max(0, target - value.count - 2)
        return String(openingDelimiter)
            + value
            + String(repeating: String(paddingCharacter), count: padding)
            + String(closingDelimiter)
    }
}
