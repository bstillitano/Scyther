//
//  WaterfallDetailRowLayoutTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

/// Covers whether the detail row's stacked host-and-path label actually fits the row height it is
/// drawn inside, at real Dynamic Type sizes.
///
/// `WaterfallDetailRow.rowHeight` is a `@ScaledMetric(relativeTo: .caption)` over
/// ``WaterfallChartStyle/rowHeight``, and the label it holds when ``WaterfallViewModel/showsHost``
/// is true is two lines set in two *different* text styles — `.caption` for the host, `.subheadline`
/// for the path — which are not guaranteed to grow at the same rate `.caption` alone does as the
/// reader's text size increases. A `@ScaledMetric` cannot be read outside a view's environment, so
/// this reconstructs the same arithmetic it is documented to use —
/// `UIFontMetrics(forTextStyle:).scaledValue(for:)` — against real `UIFont.preferredFont(forTextStyle:)`
/// line heights for both styles, at real content size categories, rather than guessing at whether
/// two lines fit inside one row.
///
/// This is a proxy for `@ScaledMetric`, not the SwiftUI runtime's own value, and reconstructing the
/// row's actual on-screen height from these numbers is still something only running the app can
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

    /// Not an assertion. `@ScaledMetric(relativeTo: .caption)` scales the row by how `.caption`
    /// alone grows between content size categories, but the stacked label also carries a
    /// `.subheadline` line — and the accessibility categories do not necessarily grow every text
    /// style at the same rate relative to one another. This records what the two figures actually
    /// are at the largest accessibility category so the fix report can say plainly whether the row
    /// clips there, rather than asserting a number nobody checked or omitting the question.
    func testWhatHappensAtTheLargestAccessibilityCategory() throws {
        let category = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let rowHeight = scaledRowHeight(for: category)
        let labelHeight = stackedLabelHeight(for: category)
        let outcome = labelHeight > rowHeight ? "would need more height than the row provides" : "still fits"
        // XCTAttachment-free, so it survives into `xcodebuild test`'s plain-text log without
        // requiring the result bundle to be opened.
        print("WaterfallDetailRowLayoutTests: at \(category.rawValue), the scaled row is "
              + "\(rowHeight)pt and the stacked label needs \(labelHeight)pt — the label \(outcome).")
        XCTAssertGreaterThan(rowHeight, 0, "sanity: the scaled row height is not zero or negative")
        XCTAssertGreaterThan(labelHeight, 0, "sanity: the measured label height is not zero or negative")
    }
}
