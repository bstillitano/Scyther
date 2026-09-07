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

    func testAccentingHandlesATrailingPercent() {
        XCTAssertEqual(PseudoLocalizationTransform.accentuate("done %"), "ðöñé %")
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
        let result = PseudoLocalizationTransform.apply(to: "Hello", key: "Hello", modes: [.accented, .lengthened])
        XCTAssertTrue(result.hasPrefix("["), "\(result) does not start with a plain bracket")
        XCTAssertTrue(result.hasSuffix("]"), "\(result) does not end with a plain bracket")
        XCTAssertTrue(result.contains("Ĥéļļö"), "\(result) does not contain the accented original")
    }

    func testAccentedOnlyDoesNotBracket() {
        XCTAssertFalse(PseudoLocalizationTransform.apply(to: "Hello", key: "Hello", modes: .accented).contains("["))
    }

    // MARK: - Modes

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
