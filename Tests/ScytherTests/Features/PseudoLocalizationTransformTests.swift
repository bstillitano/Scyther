//
//  PseudoLocalizationTransformTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class PseudoLocalizationTransformTests: XCTestCase {

    // MARK: - Accenting

    func testAccentingLeavesNoPlainLatinLetters() {
        let accented = PseudoLocalizationTransform.accentuate("The quick brown fox jumps over the lazy dog")
        XCTAssertFalse(accented.contains(where: { $0.isASCII && $0.isLetter }),
                       "\(accented) still contains plain ASCII letters")
    }

    func testAccentingKeepsTheStringRecognisable() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("Hello"), "Ĥéļļö")
    }

    func testAccentingLeavesDigitsPunctuationAndSpacesAlone() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("12:30 — 4,5 (6)?"), "12:30 — 4,5 (6)?")
    }

    func testAccentingLeavesNonLatinScriptsAlone() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("設定 Настройки"), "設定 Настройки")
    }

    func testAccentingPreservesObjectAndIntegerSpecifiers() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("Sent %@ in %lld ms"), "Šéñţ %@ îñ %lld ɱš")
    }

    func testAccentingPreservesPositionalSpecifiers() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("%2$@ of %1$lld"), "%2$@ öƒ %1$lld")
    }

    func testAccentingPreservesPrecisionSpecifiers() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("at %.2f fps"), "åţ %.2f ƒþš")
    }

    func testAccentingPreservesWidthAndFlagSpecifiers() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("id %-08d end"), "îð %-08d éñð")
    }

    func testAccentingPreservesEscapedPercentAndAccentsWhatFollows() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("100%% done"), "100%% ðöñé")
    }

    func testAccentingAccentsAfterABarePercentThatStartsNoSpecifier() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("50% off"), "50% öƒƒ")
    }

    func testAccentingTreatsASpaceFlaggedConversionAsOrdinaryCopy() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("100% and up"), "100% åñð ûþ")
    }

    func testAPercentFollowedByASpaceIsNotASpecifier() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("%l off"), "%ļ öƒƒ")
    }

    func testAccentingHandlesATrailingPercent() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("done %"), "ðöñé %")
    }

    // MARK: - Plurals

    func testAccentingPreservesStringsdictVariables() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("%#@count@ items"), "%#@count@ îţéɱš")
    }

    func testAccentingPreservesStringsdictVariablesWhoseNamesLookLikeLengthModifiers() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("%#@lld_count@ found"), "%#@lld_count@ ƒöûñð")
    }

    func testNoTextModeTouchesAStringsdictFormat() {
        let format = "%#@count@ items"
        let combinations: [PseudoLocalizationMode] = [
            .accented, .lengthened, .showsKeys,
            [.accented, .lengthened], [.accented, .showsKeys], [.accented, .lengthened, .showsKeys],
        ]
        for modes in combinations {
            XCTAssertEqual(
                PseudoLocalizationTransform.apply(to: format, key: "items.count", modes: modes),
                format,
                "modes \(modes.rawValue) corrupted a plural format"
            )
        }
    }

    func testAnUnclosedStringsdictVariableIsTreatedAsOrdinaryCopy() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("%#@count items"), "%#@çöûñţ îţéɱš")
    }

    func testAPluralFormatIsRecognisedByItsVariableMarker() {
        XCTAssertTrue(PseudoLocalizationTransform.carriesPluralConfiguration("%#@count@ items"))
    }

    func testAnOrdinaryFormatIsNotMistakenForAPluralOne() {
        XCTAssertFalse(PseudoLocalizationTransform.carriesPluralConfiguration("Selected %lld items"))
        XCTAssertFalse(PseudoLocalizationTransform.carriesPluralConfiguration("100% @ home"))
    }

    // MARK: - Opaque tokens

    func testAccentingPreservesURLs() {
        XCTAssertEqual(
            PseudoLocalizationTransform.accentuate("Visit https://example.com today"),
            "Ṽîšîţ https://example.com ţöðåý"
        )
    }

    func testAccentingPreservesSchemelessWebAddresses() {
        XCTAssertEqual(
            PseudoLocalizationTransform.accentuate("go to www.example.com now"),
            "ğö ţö www.example.com ñöŵ"
        )
    }

    func testAccentingPreservesEmailAddresses() {
        XCTAssertEqual(
            PseudoLocalizationTransform.accentuate("Email user@example.com now"),
            "Éɱåîļ user@example.com ñöŵ"
        )
    }

    func testAccentingPreservesBracePlaceholders() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("Tap {name} here"), "Ţåþ {name} ĥéŕé")
    }

    func testAccentingTreatsAMentionAsOrdinaryCopy() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("@team"), "@ţéåɱ")
    }

    func testAccentingTreatsALoneBraceAsOrdinaryCopy() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("a { b }"), "å { ƀ }")
    }

    func testAnObjectSpecifierAtATokenStartIsStillASpecifierRatherThanAnEmailAddress() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("%@ sent"), "%@ šéñţ")
    }

    func testLengtheningPutsItsPaddingOutsideAURL() {
        let lengthened = PseudoLocalizationTransform.lengthen("https://example.com")
        XCTAssertTrue(lengthened.contains("https://example.com"))
        XCTAssertTrue(lengthened.hasPrefix("["))
    }

    // MARK: - Lengthening

    func testLengtheningLandsInTheThirtyToFortyPercentBand() {
        for source in ["Save changes to your profile", "Network logs are empty", String(repeating: "a", count: 100)] {
            let ratio = Double(PseudoLocalizationTransform.lengthen(source).count) / Double(source.count)
            XCTAssertGreaterThanOrEqual(ratio, 1.30, "\(source) expanded by only \(ratio)")
            XCTAssertLessThanOrEqual(ratio, 1.40, "\(source) expanded by \(ratio)")
        }
    }

    func testLengtheningBracketsBothEnds() {
        let lengthened = PseudoLocalizationTransform.lengthen("Save changes")
        XCTAssertTrue(lengthened.hasPrefix("["))
        XCTAssertTrue(lengthened.hasSuffix("]"))
    }

    func testLengtheningKeepsTheOriginalTextIntact() {
        XCTAssertTrue(PseudoLocalizationTransform.lengthen("Save changes").contains("Save changes"))
    }

    func testLengtheningLeavesAnEmptyStringAlone() {
        XCTAssertEqual(PseudoLocalizationTransform.lengthen(""), "")
    }

    func testLengtheningAShortStringStillBracketsItEvenThoughItOvershoots() {
        XCTAssertEqual(PseudoLocalizationTransform.lengthen("OK"), "[OK]")
    }

    func testLengtheningPreservesFormatSpecifiers() {
        XCTAssertTrue(PseudoLocalizationTransform.lengthen("Sent %@ in %lld ms").contains("%lld"))
    }

    // MARK: - Combining

    func testNoModesLeavesTheValueUntouched() {
        XCTAssertEqual(PseudoLocalizationTransform.apply(to: "Hello", key: "Hello", modes: []), "Hello")
    }

    func testRightToLeftAloneLeavesTheValueUntouched() {
        XCTAssertEqual(PseudoLocalizationTransform.apply(to: "Hello", key: "Hello", modes: .rightToLeft), "Hello")
    }

    func testShowingKeysReturnsTheKey() {
        XCTAssertEqual(
            PseudoLocalizationTransform.apply(to: "Selected 5 items", key: "Selected %lld items", modes: .showsKeys),
            "Selected %lld items"
        )
    }

    func testShowingKeysWinsOverAccentingAndLengthening() {
        XCTAssertEqual(
            PseudoLocalizationTransform.apply(
                to: "Selected 5 items",
                key: "Selected %lld items",
                modes: [.showsKeys, .accented, .lengthened]
            ),
            "Selected %lld items"
        )
    }

    func testAccentingRunsBeforeLengtheningSoDelimitersStayPlain() {
        let result = PseudoLocalizationTransform.apply(
            to: "Hello",
            key: "Hello",
            modes: [.accented, .lengthened, .showsBoundaries]
        )
        XCTAssertTrue(result.hasPrefix("["), "\(result) does not start with a plain bracket")
        XCTAssertTrue(result.hasSuffix("]"), "\(result) does not end with a plain bracket")
        XCTAssertTrue(result.contains("Ĥéļļö"), "\(result) does not contain the accented original")
    }

    func testAccentedOnlyDoesNotBracket() {
        XCTAssertFalse(PseudoLocalizationTransform.apply(to: "Hello", key: "Hello", modes: .accented).contains("["))
    }

    // MARK: - Boundaries

    func testLengtheningWithoutBoundariesDropsTheBrackets() {
        let result = PseudoLocalizationTransform.apply(to: "Save changes", key: "Save changes", modes: .lengthened)
        XCTAssertFalse(result.contains("["))
        XCTAssertFalse(result.contains("]"))
        XCTAssertTrue(result.contains("Save changes"))
        XCTAssertTrue(result.contains(String(PseudoLocalizationTransform.paddingCharacter)))
    }

    func testLengtheningWithBoundariesKeepsTheBrackets() {
        let result = PseudoLocalizationTransform.apply(
            to: "Save changes",
            key: "Save changes",
            modes: [.lengthened, .showsBoundaries]
        )
        XCTAssertTrue(result.hasPrefix("["))
        XCTAssertTrue(result.hasSuffix("]"))
    }

    /// The brackets are counted towards the target either way, so switching them off gives their
    /// two characters back to the padding rather than shortening the result.
    func testBothFormsExpandByTheSameAmount() {
        for source in ["Save changes to your profile", "Network logs are empty"] {
            XCTAssertEqual(
                PseudoLocalizationTransform.lengthen(source, showingBoundaries: true).count,
                PseudoLocalizationTransform.lengthen(source, showingBoundaries: false).count,
                "\(source) expanded differently with and without its boundaries"
            )
        }
    }

    func testAccentingWithoutBoundariesIsUnchanged() {
        let withBoundaries = PseudoLocalizationTransform.apply(
            to: "Hello",
            key: "Hello",
            modes: [.accented, .showsBoundaries]
        )
        let without = PseudoLocalizationTransform.apply(to: "Hello", key: "Hello", modes: .accented)
        XCTAssertEqual(withBoundaries, "Ĥéļļö")
        XCTAssertEqual(without, "Ĥéļļö")
    }

    func testShowingKeysIsUnaffectedByBoundaries() {
        for modes: PseudoLocalizationMode in [.showsKeys, [.showsKeys, .showsBoundaries]] {
            XCTAssertEqual(
                PseudoLocalizationTransform.apply(to: "Selected 5 items", key: "Selected %lld items", modes: modes),
                "Selected %lld items"
            )
        }
    }

    func testAccentingAndLengtheningWithoutBoundariesKeepsTheAccentedOriginal() {
        let result = PseudoLocalizationTransform.apply(to: "Hello", key: "Hello", modes: [.accented, .lengthened])
        XCTAssertTrue(result.hasPrefix("Ĥéļļö"), "\(result) does not start with the accented original")
        XCTAssertFalse(result.contains("["))
    }

    /// The mode modifies the others rather than transforming anything itself, so on its own — and
    /// alongside a mode that changes no text — it must do nothing at all.
    func testBoundariesAloneChangeNothing() {
        let combinations: [PseudoLocalizationMode] = [
            .showsBoundaries,
            [],
            [.showsBoundaries, .rightToLeft],
            .rightToLeft,
        ]
        for modes in combinations {
            XCTAssertEqual(
                PseudoLocalizationTransform.apply(to: "Save changes", key: "Save changes", modes: modes),
                "Save changes",
                "modes \(modes.rawValue) transformed a string with no text mode on"
            )
        }
    }

    func testSwitchingBoundariesOffChangesNothingWhenNoTextModeIsOn() {
        XCTAssertEqual(
            PseudoLocalizationTransform.apply(to: "Save changes", key: "Save changes", modes: .showsBoundaries),
            PseudoLocalizationTransform.apply(to: "Save changes", key: "Save changes", modes: [])
        )
    }

    func testLengtheningWithoutBoundariesLeavesAnEmptyStringAlone() {
        XCTAssertEqual(PseudoLocalizationTransform.lengthen("", showingBoundaries: false), "")
    }

    // MARK: - Modes

    func testShowingBoundariesIsNotATextMode() {
        XCTAssertFalse(PseudoLocalizationMode.textAffecting.contains(.showsBoundaries))
    }

    func testTextAffectingExcludesRightToLeft() {
        XCTAssertFalse(PseudoLocalizationMode.textAffecting.contains(.rightToLeft))
    }

    func testTextAffectingContainsTheThreeTextModes() {
        XCTAssertTrue(PseudoLocalizationMode.textAffecting.contains(.accented))
        XCTAssertTrue(PseudoLocalizationMode.textAffecting.contains(.lengthened))
        XCTAssertTrue(PseudoLocalizationMode.textAffecting.contains(.showsKeys))
    }
}
#endif
