//
//  ViewThumbnailRendererTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

/// Branch and sizing coverage for the one part of the inspector that rasterises.
///
/// Deliberately not a test of what the image *looks like*: the spec puts thumbnail fidelity in
/// the "not unit-tested, verified by hand" list, because nothing here can assert that a rendered
/// view resembles the view. What is testable — and what these cover — is which of the four
/// answers comes back, and that the cap is honoured.
@MainActor
final class ViewThumbnailRendererTests: XCTestCase {

    private func makeView(width: CGFloat, height: CGFloat) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        view.backgroundColor = .red
        return view
    }

    // MARK: - The four answers

    /// A node whose view has been deallocated since the snapshot was taken.
    func testANilViewIsUnavailable() {
        XCTAssertEqual(ViewThumbnailRenderer.thumbnail(of: nil, isHidden: false, isZeroSize: false),
                       .unavailable)
    }

    func testAHiddenViewReportsHidden() {
        let view = makeView(width: 100, height: 44)
        XCTAssertEqual(ViewThumbnailRenderer.thumbnail(of: view, isHidden: true, isZeroSize: false),
                       .hidden)
    }

    func testAZeroSizeViewReportsZeroSize() {
        let view = makeView(width: 100, height: 0)
        XCTAssertEqual(ViewThumbnailRenderer.thumbnail(of: view, isHidden: false, isZeroSize: true),
                       .zeroSize)
    }

    /// The flags are the caller's answer, but a view with no area cannot be rendered whatever the
    /// caller says, so the bounds are checked too.
    func testAViewWithNoAreaIsZeroSizeEvenWhenTheFlagSaysOtherwise() {
        let view = makeView(width: 0, height: 44)
        XCTAssertEqual(ViewThumbnailRenderer.thumbnail(of: view, isHidden: false, isZeroSize: false),
                       .zeroSize)
    }

    func testAVisibleSizedViewRenders() {
        let view = makeView(width: 100, height: 44)
        guard case .image = ViewThumbnailRenderer.thumbnail(of: view, isHidden: false, isZeroSize: false) else {
            return XCTFail("a visible, sized view should render")
        }
    }

    /// Pins the precedence rather than leaving it to whichever guard happens to come first.
    ///
    /// Zero size wins because it is the more specific answer: "this view has no area" tells you
    /// something about the layout, where "this view is invisible" would leave you wondering
    /// whether unhiding it would show anything.
    func testZeroSizeWinsOverHiddenWhenBothAreTrue() {
        let view = makeView(width: 100, height: 0)
        XCTAssertEqual(ViewThumbnailRenderer.thumbnail(of: view, isHidden: true, isZeroSize: true),
                       .zeroSize)
    }

    // MARK: - The cap

    func testAnOversizedViewIsCappedOnBothAxes() throws {
        let view = makeView(width: 1024, height: 2048)
        guard case let .image(image) = ViewThumbnailRenderer.thumbnail(of: view,
                                                                      isHidden: false,
                                                                      isZeroSize: false) else {
            return XCTFail("expected an image")
        }

        XCTAssertLessThanOrEqual(image.size.width, ViewThumbnailRenderer.maximumSize.width)
        XCTAssertLessThanOrEqual(image.size.height, ViewThumbnailRenderer.maximumSize.height)
    }

    func testTheCapPreservesTheAspectRatio() throws {
        let view = makeView(width: 1024, height: 2048)
        guard case let .image(image) = ViewThumbnailRenderer.thumbnail(of: view,
                                                                      isHidden: false,
                                                                      isZeroSize: false) else {
            return XCTFail("expected an image")
        }

        XCTAssertEqual(image.size.width / image.size.height, 0.5, accuracy: 0.001,
                       "a capped thumbnail must not be stretched")
    }

    /// The `min(1, …)` in the scale exists for this: a small view is rendered at its own size
    /// rather than blown up to fill the cap, which would make a 20-point button look like a
    /// 512-point one and misreport the only thing the thumbnail is for.
    func testAViewSmallerThanTheCapIsNotUpscaled() throws {
        let view = makeView(width: 120, height: 40)
        guard case let .image(image) = ViewThumbnailRenderer.thumbnail(of: view,
                                                                      isHidden: false,
                                                                      isZeroSize: false) else {
            return XCTFail("expected an image")
        }

        XCTAssertEqual(image.size.width, 120, accuracy: 0.001)
        XCTAssertEqual(image.size.height, 40, accuracy: 0.001)
    }

    /// A view exactly at the cap is left alone rather than being scaled by a hair.
    func testAViewExactlyAtTheCapIsUnscaled() throws {
        let view = makeView(width: ViewThumbnailRenderer.maximumSize.width,
                            height: ViewThumbnailRenderer.maximumSize.height)
        guard case let .image(image) = ViewThumbnailRenderer.thumbnail(of: view,
                                                                      isHidden: false,
                                                                      isZeroSize: false) else {
            return XCTFail("expected an image")
        }

        XCTAssertEqual(image.size, ViewThumbnailRenderer.maximumSize)
    }
}
