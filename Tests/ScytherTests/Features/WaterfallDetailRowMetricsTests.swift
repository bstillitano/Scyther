//
//  WaterfallDetailRowMetricsTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

/// Covers `WaterfallDetailRowMetrics.layout(rowWidth:scaledLabelWidth:scaledDurationWidth:)`
/// against the row's own width, which is the thing `WaterfallDetailRowLayoutTests` never measures:
/// that file asks whether each column fits *its own* text, never whether the label, plot and
/// duration columns together fit the row that holds all three. A row can pass every assertion in
/// that file — the duration column is always wide enough for the duration text it draws — while
/// still overflowing its own width, because nothing there ever adds the columns up against the
/// space actually available. This file is that addition.
///
/// Like `WaterfallDetailRowLayoutTests`, this reconstructs `@ScaledMetric`'s arithmetic with
/// `UIFontMetrics(forTextStyle:).scaledValue(for:compatibleWith:)` rather than reading a live
/// `@ScaledMetric` — which cannot be read outside a view's environment — so this is a proxy for
/// what `WaterfallView` actually computes at runtime, not a measurement of it. It is honest about
/// that for the same reason that file is: confirming the row genuinely never overflows on screen,
/// at every device width the toolkit supports, is something only running the app can do.
final class WaterfallDetailRowMetricsTests: XCTestCase {

    /// `@ScaledMetric(relativeTo: .caption)` applied to ``WaterfallChartStyle/detailLabelWidth``,
    /// the way `WaterfallView.scaledLabelWidth` computes it.
    ///
    /// - Parameter category: The content size category to scale for.
    /// - Returns: The label column's naive (pre-``WaterfallDetailRowMetrics`` cap) width.
    private func scaledLabelWidth(for category: UIContentSizeCategory) -> CGFloat {
        let trait = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: .caption1)
            .scaledValue(for: WaterfallChartStyle.detailLabelWidth, compatibleWith: trait)
    }

    /// `@ScaledMetric(relativeTo: .caption)` applied to ``WaterfallChartStyle/detailDurationWidth``,
    /// the way `WaterfallView.scaledDurationWidth` computes it.
    ///
    /// - Parameter category: The content size category to scale for.
    /// - Returns: The duration column's naive (pre-``WaterfallDetailRowMetrics`` cap) width.
    private func scaledDurationWidth(for category: UIContentSizeCategory) -> CGFloat {
        let trait = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: .caption1)
            .scaledValue(for: WaterfallChartStyle.detailDurationWidth, compatibleWith: trait)
    }

    /// Asserts the three widths a `Layout` reports never draw the row wider than `rowWidth`
    /// itself, which is the one guarantee every caller of this type depends on regardless of
    /// content size category.
    private func assertFits(_ layout: WaterfallDetailRowMetrics.Layout, in rowWidth: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) {
        let total = layout.labelWidth + layout.plotWidth + layout.durationWidth + WaterfallDetailRowMetrics.fixedChrome
        XCTAssertLessThanOrEqual(total, rowWidth + 0.01,
                                 "the row's three columns plus its fixed chrome need \(total)pt against a \(rowWidth)pt row",
                                 file: file, line: line)
        XCTAssertGreaterThanOrEqual(layout.labelWidth, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(layout.durationWidth, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(layout.plotWidth, 0, file: file, line: line)
    }

    // MARK: - Default size

    /// At the default content size the two scaled columns are barely off their base 132pt/62pt
    /// values, so an ordinary row — wide enough for a `List` on any supported device — has room
    /// for both at full width and still clears ``WaterfallChartStyle/minimumPlotWidth`` with a lot
    /// to spare. This is the case ``WaterfallDetailRowMetrics/layout(rowWidth:scaledLabelWidth:scaledDurationWidth:)``
    /// must leave alone entirely: nothing here should be capped.
    func testAtTheDefaultTextSizeTheColumnsFitUncappedAndThePlotClearsItsFloor() {
        let rowWidth: CGFloat = 350
        let naiveLabelWidth = scaledLabelWidth(for: .large)
        let naiveDurationWidth = scaledDurationWidth(for: .large)
        let layout = WaterfallDetailRowMetrics.layout(rowWidth: rowWidth,
                                                       scaledLabelWidth: naiveLabelWidth,
                                                       scaledDurationWidth: naiveDurationWidth)
        assertFits(layout, in: rowWidth)
        XCTAssertEqual(layout.labelWidth, naiveLabelWidth, accuracy: 0.01,
                       "the default size shouldn't need to cap the label column at all")
        XCTAssertEqual(layout.durationWidth, naiveDurationWidth, accuracy: 0.01,
                       "the default size shouldn't need to cap the duration column at all")
        XCTAssertGreaterThan(layout.plotWidth, WaterfallChartStyle.minimumPlotWidth,
                             "an ordinary row at the default text size should give the plot real room, not just its floor")
    }

    // MARK: - Largest accessibility category

    /// The finding this file exists to close: at `accessibilityExtraExtraExtraLarge` the two
    /// `@ScaledMetric` columns alone demand roughly 421pt and 198pt together — measured here, not
    /// assumed — against a row nowhere near that wide. Uncapped, the flexible plot column between
    /// them would be asked for a negative width, which SwiftUI clamps to zero: the bar vanishes
    /// and the row still overflows the screen because `.frame(width:)` does not compress. This
    /// proves the cap actually engages, that it never lets the row's total exceed `rowWidth`, and
    /// that the plot still gets its floor once the two text columns give way — the row keeps its
    /// most distinguishing feature, the overlap between bars, at exactly the size where a reader
    /// most needs the row to still make sense.
    func testAtTheLargestAccessibilityCategoryTheColumnsAreCappedAndThePlotStillClearsItsFloor() {
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let naiveLabelWidth = scaledLabelWidth(for: category)
        let naiveDurationWidth = scaledDurationWidth(for: category)
        // A representative detail-list content width at this category, per the finding this test
        // was written for: the two naive columns alone (~421pt + ~198pt) already exceed it.
        let rowWidth: CGFloat = 358
        XCTAssertGreaterThan(naiveLabelWidth + naiveDurationWidth, rowWidth,
                             "this test only proves anything if the naive columns genuinely don't fit \(rowWidth)pt")

        let layout = WaterfallDetailRowMetrics.layout(rowWidth: rowWidth,
                                                       scaledLabelWidth: naiveLabelWidth,
                                                       scaledDurationWidth: naiveDurationWidth)
        assertFits(layout, in: rowWidth)
        XCTAssertEqual(layout.plotWidth, WaterfallChartStyle.minimumPlotWidth, accuracy: 0.01,
                       "once the naive columns don't fit, the plot should be given exactly its floor, not squeezed below it")
        XCTAssertLessThan(layout.labelWidth, naiveLabelWidth,
                          "the label column should actually have been capped down from its naive scaled width")
        XCTAssertLessThan(layout.durationWidth, naiveDurationWidth,
                          "the duration column should actually have been capped down from its naive scaled width")
        // The cap scales both columns by the same factor, so the ratio `@ScaledMetric` chose
        // between them survives: the label — wider at every text size, per its 132:62 base split —
        // should still end up wider than the duration column after capping, not the other way
        // round.
        XCTAssertGreaterThan(layout.labelWidth, layout.durationWidth,
                             "capping shouldn't invert which column is wider")
    }

    /// Confirms the previous test's premise holds for the *actual* `@ScaledMetric` base values
    /// this feature ships, not just for the finding's illustrative 421pt/198pt figures — so a
    /// future change to ``WaterfallChartStyle/detailLabelWidth`` or
    /// ``WaterfallChartStyle/detailDurationWidth`` that accidentally made the naive columns small
    /// enough to always fit would surface here as a coverage gap rather than silently stop
    /// exercising the cap at all.
    func testTheNaiveColumnsGenuinelyExceedAnOrdinaryRowAtTheLargestAccessibilityCategory() {
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let naiveTotal = scaledLabelWidth(for: category) + scaledDurationWidth(for: category)
        let ordinaryRowWidth: CGFloat = 350
        XCTAssertGreaterThan(naiveTotal, ordinaryRowWidth,
                             "the cap in WaterfallDetailRowMetrics.layout(rowWidth:scaledLabelWidth:scaledDurationWidth:) "
                             + "has nothing to do at AX5 if the naive columns (\(naiveTotal)pt) already fit an ordinary "
                             + "\(ordinaryRowWidth)pt row")
    }

    // MARK: - Degenerate widths

    /// A row narrower even than the fixed chrome and the plot's own floor together is not
    /// something any supported device width produces, but the function still has to fail
    /// gracefully rather than produce a negative or NaN width a `View` would crash or misdraw on.
    func testAVeryNarrowRowNeverProducesNegativeWidths() {
        let layout = WaterfallDetailRowMetrics.layout(rowWidth: 20,
                                                       scaledLabelWidth: scaledLabelWidth(for: .accessibilityExtraExtraExtraLarge),
                                                       scaledDurationWidth: scaledDurationWidth(for: .accessibilityExtraExtraExtraLarge))
        XCTAssertGreaterThanOrEqual(layout.labelWidth, 0)
        XCTAssertGreaterThanOrEqual(layout.durationWidth, 0)
        XCTAssertGreaterThanOrEqual(layout.plotWidth, 0)
        // The one promise that still has to hold even here: the plot is never reported as wider
        // than the row itself.
        XCTAssertLessThanOrEqual(layout.plotWidth, 20)
    }

    /// A zero-width row — the transient state a `GeometryReader` can report for one frame before
    /// layout settles — must not divide by zero when the naive columns are capped.
    func testAZeroWidthRowDoesNotDivideByZero() {
        let layout = WaterfallDetailRowMetrics.layout(rowWidth: 0,
                                                       scaledLabelWidth: scaledLabelWidth(for: .accessibilityExtraExtraExtraLarge),
                                                       scaledDurationWidth: scaledDurationWidth(for: .accessibilityExtraExtraExtraLarge))
        XCTAssertEqual(layout.labelWidth, 0, accuracy: 0.001)
        XCTAssertEqual(layout.durationWidth, 0, accuracy: 0.001)
        XCTAssertEqual(layout.plotWidth, 0, accuracy: 0.001)
    }
}
