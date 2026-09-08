//
//  LayoutGuidesTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class LayoutGuidesTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    func testASafeAreaLineIsDrawnForEachNonZeroInset() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            margins: .zero,
            in: bounds
        )
        let safeArea = lines.filter { $0.kind == .safeArea }
        XCTAssertEqual(safeArea.count, 2)
        XCTAssertEqual(Set(safeArea.map(\.value)), [59, 34])
    }

    /// A line labelled `0.0 pt` flush against the screen edge is noise, and on a device with no
    /// home indicator the bottom inset genuinely is zero.
    func testAZeroInsetIsNotDrawn() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        XCTAssertEqual(lines.filter { $0.kind == .safeArea }.count, 1)
    }

    func testMarginsAreDrawnSeparatelyFromSafeAreas() {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
            in: bounds
        )
        XCTAssertEqual(lines.filter { $0.kind == .margin }.count, 2)
        XCTAssertEqual(lines.filter { $0.kind == .safeArea }.count, 1)
    }

    /// Corrected from the brief: uses `try XCTUnwrap` on a `throws` test rather than `try?`
    /// swallowing the unwrap failure, so an empty `lines` result fails loudly at the unwrap
    /// rather than silently comparing `nil` against a concrete point two lines later.
    func testATopInsetLineSpansTheFullWidthAtItsOwnDepth() throws {
        let lines = LayoutGuidesView.guideLines(
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0),
            margins: .zero,
            in: bounds
        )
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.start, CGPoint(x: 0, y: 59))
        XCTAssertEqual(line.end, CGPoint(x: 400, y: 59))
    }

    func testNothingIsDrawnWhenEveryInsetIsZero() {
        let lines = LayoutGuidesView.guideLines(safeArea: .zero, margins: .zero, in: bounds)
        XCTAssertTrue(lines.isEmpty)
    }

    // MARK: - Settings

    func testTheGuidesAreOffByDefault() {
        let suite = "LayoutGuidesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(defaults.bool(forKey: LayoutGuides.EnabledDefaultsKey),
                       "an overlay that is quietly on is an overlay the developer will blame the app for")
    }
}
