//
//  WaterfallDetailRowLayoutTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

/// Covers whether the detail row's content actually fits the space it is drawn inside, at real
/// Dynamic Type sizes — vertically, whether the stacked host-and-path label fits the row height,
/// and horizontally, whether the duration label fits the duration column's own width.
///
/// `WaterfallDetailRow.rowHeight`, `.labelWidth` and `.durationWidth` are each a
/// `@ScaledMetric(relativeTo: .caption)` over their ``WaterfallChartStyle`` base value. The
/// vertical question is the harder one to trust by inspection: the stacked label holds two lines
/// set in two *different* text styles — `.caption` for the host, `.subheadline` for the path —
/// which are not guaranteed to grow at the same rate `.caption` alone does as the reader's text
/// size increases. A `@ScaledMetric` cannot be read outside a view's environment, so this
/// reconstructs the same arithmetic it is documented to use —
/// `UIFontMetrics(forTextStyle:).scaledValue(for:)` — against real `UIFont.preferredFont(forTextStyle:)`
/// line heights and real rendered text widths, at real content size categories, rather than
/// guessing at whether the row's content fits.
///
/// This is a proxy for `@ScaledMetric`, not the SwiftUI runtime's own value, and reconstructing the
/// row's actual on-screen layout from these numbers is still something only running the app can
/// confirm — see the fix report this test was written for.
final class WaterfallDetailRowLayoutTests: XCTestCase {

    /// The gap `WaterfallDetailRow`'s `VStack(alignment: .leading, spacing: 1)` puts between the
    /// host and the path.
    private let stackedLineSpacing: CGFloat = 1

    /// `@ScaledMetric(relativeTo: .caption)` applied to ``WaterfallChartStyle/rowHeight``, the way
    /// `WaterfallDetailRow.rowHeight` computes it. `UIFontMetrics` is what Apple documents
    /// `@ScaledMetric` as being built on.
    ///
    /// - Parameter category: The content size category to scale for.
    /// - Returns: The row height a `WaterfallDetailRow` would be given at that category.
    private func scaledRowHeight(for category: UIContentSizeCategory) -> CGFloat {
        let trait = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: .caption1)
            .scaledValue(for: WaterfallChartStyle.rowHeight, compatibleWith: trait)
    }

    /// How tall the stacked host-and-path label actually needs to be at `category`: one line of
    /// `.caption` for the host, one of `.subheadline` for the path, and the stack's own spacing.
    ///
    /// - Parameter category: The content size category to measure at.
    /// - Returns: The label's required height, in points.
    private func stackedLabelHeight(for category: UIContentSizeCategory) -> CGFloat {
        let trait = UITraitCollection(preferredContentSizeCategory: category)
        let host = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: trait).lineHeight
        let path = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: trait).lineHeight
        return host + stackedLineSpacing + path
    }

    /// `@ScaledMetric(relativeTo: .caption)` applied to ``WaterfallChartStyle/detailDurationWidth``,
    /// the way `WaterfallDetailRow.durationWidth` computes it.
    ///
    /// - Parameter category: The content size category to scale for.
    /// - Returns: The duration column's width at that category.
    private func scaledDurationWidth(for category: UIContentSizeCategory) -> CGFloat {
        let trait = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: .caption1)
            .scaledValue(for: WaterfallChartStyle.detailDurationWidth, compatibleWith: trait)
    }

    /// How wide a representative duration label actually renders at `category`, in the `.caption`
    /// font ``WaterfallDetailRow`` draws its duration text in.
    ///
    /// `1,380 ms` — one of the longer ordinary readings a bar's duration formats to, from
    /// `DurationText.milliseconds(_:)` — rather than a short one: the spec this row was rebuilt
    /// from opens by naming exactly this failure, duration text clipped for a 1.25 second request.
    ///
    /// - Parameter category: The content size category to measure at.
    /// - Returns: The rendered text's width, in points.
    private func durationTextWidth(for category: UIContentSizeCategory) -> CGFloat {
        let trait = UITraitCollection(preferredContentSizeCategory: category)
        let font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: trait)
        let text = DurationText.milliseconds(1_380)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// At the default content size — where the vast majority of the toolkit's users read the
    /// page — the stacked label has to fit inside the row height with room to spare. The row also
    /// centres a bar and a duration label vertically; a label that merely does not clip would
    /// still read as cramped if it left no air around it.
    func testTheStackedLabelFitsComfortablyInsideTheRowHeightAtTheDefaultTextSize() {
        let rowHeight = scaledRowHeight(for: .large)
        let labelHeight = stackedLabelHeight(for: .large)
        print("WaterfallDetailRowLayoutTests: at .large (default), the row is \(rowHeight)pt and "
              + "the stacked label needs \(labelHeight)pt.")
        XCTAssertLessThan(labelHeight, rowHeight,
                          "the stacked host and path need \(labelHeight)pt against a \(rowHeight)pt row")
    }

    /// `@ScaledMetric(relativeTo: .caption)` scales the row by how `.caption` alone grows between
    /// content size categories, but the stacked label also carries a `.subheadline` line — and the
    /// accessibility categories do not necessarily grow every text style at the same rate relative
    /// to one another. This used to record the two figures with `print` and assert only that
    /// neither was zero, which checked nothing about whether the row actually clips — the question
    /// the test exists to answer. Measured at the largest accessibility category the stacked label
    /// still fits comfortably (110.8pt needed against a 140.3pt row on the simulator this was
    /// measured on), so this now asserts that outright, the same way the default-size test above
    /// does; a regression that closed the gap would fail it rather than pass silently.
    func testTheStackedLabelStillFitsInsideTheRowHeightAtTheLargestAccessibilityCategory() {
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let rowHeight = scaledRowHeight(for: category)
        let labelHeight = stackedLabelHeight(for: category)
        XCTAssertLessThan(labelHeight, rowHeight,
                          "the stacked host and path need \(labelHeight)pt against a \(rowHeight)pt row")
    }

    // MARK: - Horizontal fit

    /// At the default content size, the duration column has to fit a representative duration
    /// label with room to spare — the same standard ``testTheStackedLabelFitsComfortablyInsideTheRowHeightAtTheDefaultTextSize``
    /// holds the row height to.
    func testTheDurationColumnFitsItsTextComfortablyAtTheDefaultTextSize() {
        let columnWidth = scaledDurationWidth(for: .large)
        let textWidth = durationTextWidth(for: .large)
        XCTAssertLessThan(textWidth, columnWidth,
                          "the duration text needs \(textWidth)pt against a \(columnWidth)pt column")
    }

    /// The failure the spec this row was rebuilt from opens by naming — "Duration text runs off
    /// the right edge (`1.` for a 1.25 s request)" — reappears at accessibility sizes the moment
    /// the duration column stops growing with the reader's text size, because `.caption` scales
    /// from 11pt to 26pt at AX5 while a fixed 62pt column does not. `WaterfallDetailRow.durationWidth`
    /// is a `@ScaledMetric` for exactly this reason; this is what proves it actually keeps up.
    func testTheDurationColumnStillFitsItsTextAtTheLargestAccessibilityCategory() {
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let columnWidth = scaledDurationWidth(for: category)
        let textWidth = durationTextWidth(for: category)
        XCTAssertLessThan(textWidth, columnWidth,
                          "the duration text needs \(textWidth)pt against a \(columnWidth)pt column")
    }
}
