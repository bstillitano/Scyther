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
/// - ``lengthen(_:showingBoundaries:)``
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

    /// Marks the start of a lengthened string, when
    /// ``PseudoLocalizationMode/showsBoundaries`` is on.
    static let openingDelimiter: Character = "["

    /// Marks the end of a lengthened string, when ``PseudoLocalizationMode/showsBoundaries`` is on.
    ///
    /// The delimiters are the actual diagnostic: a missing closing bracket means the label was
    /// truncated, which is far easier to spot in a screenshot than judging whether some accented
    /// text looks a few characters short. That is why they are on by default — and why they are a
    /// switch rather than a certainty, since a developer who has read a hundred bracketed labels
    /// and only wants to see the expansion should not have to give up lengthening to stop seeing
    /// them.
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
    /// - ``PseudoLocalizationMode/showsBoundaries`` switches nothing on. It reaches only
    ///   ``lengthen(_:showingBoundaries:)``, because the brackets that mode governs are the only
    ///   delimiters anything here produces, and the guard on the first line means it cannot do
    ///   anything at all unless a text mode is already on. That is the whole of its behaviour:
    ///   with every text mode off, the string comes back untouched whichever way it is set.
    ///
    /// A string carrying plural configuration is returned untouched whatever the modes say — see
    /// ``carriesPluralConfiguration(_:)``. That refusal cannot live in ``accentuate(_:)`` alone,
    /// because lengthening and showing keys break a `.stringsdict` lookup just as thoroughly as
    /// accenting does.
    ///
    /// - Parameters:
    ///   - value: The already-resolved, already-formatted string.
    ///   - key: The catalog key `value` came from, used only by
    ///     ``PseudoLocalizationMode/showsKeys``.
    ///   - modes: The modes currently switched on.
    /// - Returns: The transformed string, or `value` unchanged when no text-affecting mode is on.
    static func apply(to value: String, key: String, modes: PseudoLocalizationMode) -> String {
        guard !modes.intersection(.textAffecting).isEmpty else { return value }
        guard !carriesPluralConfiguration(value) else { return value }
        if modes.contains(.showsKeys) { return key }

        var result = value
        if modes.contains(.accented) { result = accentuate(result) }
        if modes.contains(.lengthened) {
            result = lengthen(result, showingBoundaries: modes.contains(.showsBoundaries))
        }
        return result
    }

    // MARK: - Plurals

    /// Whether a resolved string is a `.stringsdict` format that Scyther must not touch.
    ///
    /// A `.stringsdict` entry resolves to a format containing `%#@variable@`, which
    /// `String.localizedStringWithFormat` later expands using plural configuration attached to the
    /// string Foundation returned. Scyther can preserve neither half of that reliably: accenting
    /// would rename the variable so it no longer matched the dictionary, and any transform at all
    /// produces a new string, losing the attachment — so `lengthened` and `showsKeys` would break
    /// plurals just as completely as `accented`, and the developer would see a literal
    /// `%#@count@` on screen with nothing to suggest Scyther put it there.
    ///
    /// Broken text that is not a localisation problem is the one thing this tool must never
    /// produce, so these strings are left alone entirely. The cost is that a plural label is one
    /// of the few places pseudo-localisation shows nothing; the alternative is corrupting copy
    /// Scyther does not own.
    ///
    /// `%#@` is the whole test because nothing else emits it: it is not a printf specifier, and
    /// Foundation writes it only for `.stringsdict` variables.
    ///
    /// - Parameter value: The resolved string.
    /// - Returns: `true` when the string is a plural format.
    static func carriesPluralConfiguration(_ value: String) -> Bool {
        value.contains(pluralVariablePrefix)
    }

    /// The three characters that open a `.stringsdict` variable reference.
    static let pluralVariablePrefix = "%#@"

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
        var previous: Character?
        while index < value.endIndex {
            if let end = protectedRunEnd(in: value, from: index, atTokenStart: previous?.isWhitespace ?? true) {
                result.append(contentsOf: value[index..<end])
                previous = value[value.index(before: end)]
                index = end
                continue
            }
            let character = value[index]
            result.append(accentMap[character] ?? character)
            previous = character
            index = value.index(after: index)
        }
        return result
    }

    /// The end index of a run that must be copied through verbatim, or `nil` to accent normally.
    ///
    /// Four kinds of run are protected, and the reason is the same for all four: accenting them
    /// produces a defect the developer will spend time chasing in their own code, which is the
    /// opposite of what a diagnostic tool is for.
    ///
    /// - A `.stringsdict` variable, `%#@count@`. Renamed, it stops matching the dictionary.
    /// - A printf specifier, `%@` / `%lld` / `%1$@` / `%.2f`. Mangled, the format stops formatting.
    /// - A brace placeholder, `{name}`. Cross-platform copy is commonly templated this way and
    ///   substituted later with `replacingOccurrences`, which is an exact match.
    /// - A URL or email address. Storing a support or deep-link URL in a `.strings` file is
    ///   ordinary practice, and `ĥţţþš://éẋåɱþļé.çöɱ` is a dead link, not a finding.
    ///
    /// URLs and emails are recognised only at the start of a whitespace-delimited token, and the
    /// whole token is protected including any trailing punctuation. That over-protects a full stop
    /// at the end of a sentence, which costs nothing — punctuation is not accented anyway — and it
    /// avoids the alternative of trying to decide where a URL stops, which no heuristic gets right.
    ///
    /// - Parameters:
    ///   - value: The string being scanned.
    ///   - start: The index to test.
    ///   - atTokenStart: Whether `start` begins a whitespace-delimited token.
    /// - Returns: The index just past the protected run, or `nil`.
    private static func protectedRunEnd(
        in value: String,
        from start: String.Index,
        atTokenStart: Bool
    ) -> String.Index? {
        if atTokenStart, let end = opaqueTokenEnd(in: value, from: start) { return end }
        switch value[start] {
        case "%":
            return pluralVariableEnd(in: value, from: start) ?? specifierEnd(in: value, from: start)
        case "{":
            return bracePlaceholderEnd(in: value, from: start)
        default:
            return nil
        }
    }

    /// The end index of a `%#@variable@` reference starting at `start`, or `nil` if there is none.
    ///
    /// Checked before ``specifierEnd(in:from:)`` because the generic parser would otherwise read
    /// `%#@` as a complete specifier — `#` is a legal flag and `@` a legal conversion — and go on
    /// to accent the variable name behind it.
    ///
    /// - Parameters:
    ///   - value: The string being scanned.
    ///   - start: The index of the `%`.
    /// - Returns: The index just past the closing `@`, or `nil`.
    private static func pluralVariableEnd(in value: String, from start: String.Index) -> String.Index? {
        var index = value.index(after: start)
        guard index < value.endIndex, value[index] == "#" else { return nil }
        index = value.index(after: index)
        guard index < value.endIndex, value[index] == "@" else { return nil }
        index = value.index(after: index)
        while index < value.endIndex, value[index] != "@" {
            guard !value[index].isWhitespace else { return nil }
            index = value.index(after: index)
        }
        guard index < value.endIndex else { return nil }
        return value.index(after: index)
    }

    /// The end index of a `{placeholder}` starting at `start`, or `nil` if there is none.
    ///
    /// Whitespace ends the search unsuccessfully, so an ordinary sentence that happens to contain
    /// an opening brace is still accented rather than swallowed to the end of the string.
    ///
    /// - Parameters:
    ///   - value: The string being scanned.
    ///   - start: The index of the `{`.
    /// - Returns: The index just past the `}`, or `nil`.
    private static func bracePlaceholderEnd(in value: String, from start: String.Index) -> String.Index? {
        var index = value.index(after: start)
        while index < value.endIndex, value[index] != "}" {
            guard !value[index].isWhitespace else { return nil }
            index = value.index(after: index)
        }
        guard index < value.endIndex else { return nil }
        return value.index(after: index)
    }

    /// The end index of a whitespace-delimited token that must not be accented, or `nil`.
    ///
    /// - Parameters:
    ///   - value: The string being scanned.
    ///   - start: The first character of the token.
    /// - Returns: The index just past the token, or `nil` when the token is ordinary copy.
    private static func opaqueTokenEnd(in value: String, from start: String.Index) -> String.Index? {
        var end = start
        while end < value.endIndex, !value[end].isWhitespace {
            end = value.index(after: end)
        }
        guard end > start, isOpaque(value[start..<end]) else { return nil }
        return end
    }

    /// Whether a token is a URL or an email address rather than copy.
    ///
    /// Deliberately shape-based and lenient in one direction only: it would rather leave a strange
    /// piece of copy unaccented than accent a live link. The `@` test requires something before
    /// the `@` and a dot after it, so `%@` and `@mention` are still treated as copy and reach the
    /// specifier parser.
    ///
    /// - Parameter token: The whitespace-delimited token.
    /// - Returns: `true` when the token should be copied through verbatim.
    private static func isOpaque(_ token: Substring) -> Bool {
        if token.contains("://") { return true }
        for scheme in ["www.", "mailto:", "tel:"] where token.hasPrefix(scheme) { return true }
        guard let at = token.firstIndex(of: "@"), at > token.startIndex else { return false }
        let domain = token[token.index(after: at)...]
        return domain.contains(".") && !domain.contains("@")
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
    ///
    /// There is deliberately no space in this set. A space here would make `%<space>` a complete
    /// specifier and quietly undo the space-flag decision above, which is exactly the bug this set
    /// shipped with in its first draft — and which neither of the two tests named for that
    /// behaviour could detect, because `%` and space are both absent from ``accentMap`` and the
    /// output is identical either way in the common shapes.
    private static let conversionCharacters: Set<Character> = Set("@diouxXeEfgGaAcCsSpn")

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

    /// Pads a string to roughly ``expansionFactor`` of its length, bracketed at both ends unless
    /// the developer has switched the brackets off.
    ///
    /// The brackets are counted towards the target rather than added on top of it, so the result
    /// really is about 135% and not 135% plus two. They cost the padding two characters, which
    /// matters only for strings so short that the brackets alone already overshoot — a
    /// three-character label becomes five, or 167%. That overshoot is left in deliberately: a
    /// bracket that fits is worth more than an exact ratio, because it is the bracket, not the
    /// length, that tells the developer whether the label was clipped.
    ///
    /// Without them the two characters go back to the padding rather than being lost, so both
    /// forms expand a string by the same amount and a layout that survives one survives the other.
    /// What is given up is the diagnostic: a padded label with no closing bracket is a label that
    /// grew, and there is no longer any way to tell from it whether the end was cut off. That is
    /// the trade the switch exists to offer, and the reason it ships on.
    ///
    /// An empty string is returned untouched. Bracketing nothing would turn every blank
    /// accessibility value and every empty placeholder into a visible `[]`, which reads as a
    /// rendering bug rather than as a measurement.
    ///
    /// - Parameters:
    ///   - value: The string to pad.
    ///   - showingBoundaries: Whether to mark the ends with ``openingDelimiter`` and
    ///     ``closingDelimiter``.
    /// - Returns: The padded string.
    static func lengthen(_ value: String, showingBoundaries: Bool = true) -> String {
        guard !value.isEmpty else { return value }
        let target = Int((Double(value.count) * expansionFactor).rounded())
        let delimiters = showingBoundaries ? 2 : 0
        let padding = max(0, target - value.count - delimiters)
        let body = value + String(repeating: String(paddingCharacter), count: padding)
        guard showingBoundaries else { return body }
        return String(openingDelimiter) + body + String(closingDelimiter)
    }
}
