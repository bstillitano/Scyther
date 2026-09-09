//
//  ViewDetailViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class ViewDetailViewModelTests: XCTestCase {

    private let windowBounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    /// Keeps the walked hierarchy alive for the length of the test.
    ///
    /// The snapshot's side table is weak on purpose, so a root left to go out of scope with
    /// ``makeModel(configure:)`` would take the subject view with it and every test here would
    /// quietly be exercising the deallocated case instead of the one it names.
    private var hierarchyRoot: UIView?

    private func makeModel(configure: (UIView) -> Void = { _ in }) -> ViewDetailViewModel {
        let root = UIView(frame: windowBounds)
        hierarchyRoot = root
        let subject = UIView(frame: CGRect(x: 16, y: 100, width: 200, height: 44))
        configure(subject)
        root.addSubview(subject)

        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        return ViewDetailViewModel(node: snapshot.root.children[0],
                                   snapshot: snapshot,
                                   windowBounds: windowBounds)
    }

    func testGeometryReportsTheFrameInWindowSpace() async {
        let model = makeModel()
        await model.onFirstAppear()

        let frame = model.geometry.first { $0.id == "frame" }
        XCTAssertEqual(frame?.value, "16, 100, 200 × 44")
    }

    func testAppearanceReportsAlphaAndHidden() async {
        let model = makeModel { $0.alpha = 0.5 }
        await model.onFirstAppear()

        XCTAssertEqual(model.appearance.first { $0.id == "alpha" }?.value, "0.5")
        XCTAssertNotNil(model.appearance.first { $0.id == "hidden" })
    }

    func testAVisibleViewRendersAThumbnail() async {
        let model = makeModel { $0.backgroundColor = .red }
        await model.onFirstAppear()

        guard case .image = model.thumbnail else {
            return XCTFail("a visible, sized view should render")
        }
    }

    /// Rasterisation is the one expensive thing this feature does, so it happens once in
    /// `onFirstAppear()` and the result is held. A computed property would re-render on every
    /// SwiftUI re-read — a scroll, a rotation, any other `@Published` change on the page — and
    /// every other test here passes either way, because they all read the value only once.
    func testTheThumbnailIsRenderedOnceRatherThanOnEveryRead() async {
        let model = makeModel { $0.backgroundColor = .red }
        await model.onFirstAppear()

        guard case .image(let first) = model.thumbnail,
              case .image(let second) = model.thumbnail else {
            return XCTFail("a visible, sized view should render")
        }
        XCTAssertIdentical(first, second, "reading the thumbnail twice re-rasterised the view")
    }

    /// The honesty rule: say which of the three reasons there is nothing to show, rather than
    /// presenting an empty box as though it were the view's appearance.
    func testAHiddenViewReportsHiddenRatherThanRendering() async {
        let model = makeModel { $0.isHidden = true }
        await model.onFirstAppear()

        XCTAssertEqual(model.thumbnail, .hidden)
    }

    func testAZeroSizeViewReportsZeroSize() async {
        let root = UIView(frame: windowBounds)
        let collapsed = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 0))
        root.addSubview(collapsed)
        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let model = ViewDetailViewModel(node: snapshot.root.children[0],
                                        snapshot: snapshot,
                                        windowBounds: windowBounds)

        await model.onFirstAppear()

        XCTAssertEqual(model.thumbnail, .zeroSize)
    }

    func testAViewDeallocatedSinceTheSnapshotReportsUnavailable() async {
        let root = UIView(frame: windowBounds)
        var subject: UIView? = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        root.addSubview(subject!)
        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let node = snapshot.root.children[0]

        // `removeFromSuperview()` autoreleases the view as part of its own bookkeeping — a UIKit
        // implementation detail, not anything the snapshot does — so the release needs an
        // explicit pool, exactly as `ViewHierarchyWalkerTests` drains one for the same reason.
        autoreleasepool {
            subject!.removeFromSuperview()
            subject = nil
        }

        let model = ViewDetailViewModel(node: node, snapshot: snapshot, windowBounds: windowBounds)
        await model.onFirstAppear()

        XCTAssertEqual(model.thumbnail, .unavailable)
    }

    func testContextNamesTheOwningController() async {
        let controller = UIViewController()
        controller.view.frame = windowBounds
        let subject = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
        controller.view.addSubview(subject)

        let snapshot = ViewHierarchyWalker.snapshot(of: controller.view, windowBounds: windowBounds)
        let model = ViewDetailViewModel(node: snapshot.root.children[0],
                                        snapshot: snapshot,
                                        windowBounds: windowBounds)
        await model.onFirstAppear()

        XCTAssertEqual(model.context.first { $0.id == "controller" }?.value, "UIViewController")
    }

    func testEveryFieldCarriesADistinctIdentity() async {
        let model = makeModel()
        await model.onFirstAppear()

        let ids = (model.geometry + model.appearance + model.context + model.behaviour).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate ids would collapse rows in the List")
    }
}
