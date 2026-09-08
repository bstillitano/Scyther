//
//  WaterfallPageCostTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

/// Covers what the full-log page is allowed to *cost*, which is a separate question from what it
/// draws.
///
/// The page removed the only thing that used to bound this work: the Traffic Stats section lays
/// out at most forty bars, while the page lays out whatever the log holds — thousands of entries
/// in a busy session. Two properties keep that affordable, and neither is visible from a
/// screenshot, so both are pinned here.
@MainActor
final class WaterfallPageCostTests: XCTestCase {

    /// Builds `count` captured requests one second apart.
    ///
    /// - Parameter count: How many to build.
    /// - Returns: The requests, oldest first.
    private func log(of count: Int) -> [HTTPRequest] {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            var urlRequest = URLRequest(url: URL(string: "https://api.example.com/v1/resource/\(index)")!)
            urlRequest.httpMethod = "GET"
            let model = HTTPRequest()
            model.saveRequest(urlRequest)
            model.requestDate = origin.addingTimeInterval(Double(index))
            model.requestDuration = 120
            model.responseCode = 200
            model.responseDate = origin.addingTimeInterval(Double(index) + 0.12)
            model.noResponse = false
            return model
        }
    }

    /// The layout of a thousand requests is one pass, and it is cheap enough to sit on a detached
    /// task behind a debounce without the screen ever waiting on it.
    ///
    /// The bound is deliberately loose — a shared CI machine is not a stopwatch — but it is three
    /// orders of magnitude above what the work actually costs, so a regression that made this
    /// quadratic would blow through it long before flakiness could.
    func testAThousandRequestsAreLaidOutInOnePass() {
        let requests = log(of: 1_000)
        let started = CFAbsoluteTimeGetCurrent()
        let layout = WaterfallViewModel.layout(of: requests, limit: requests.count)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        XCTAssertEqual(layout.rows.count, 1_000)
        print("WaterfallPageCostTests: 1,000 requests laid out in \(Int(elapsed * 1_000_000)) µs")
        XCTAssertLessThan(elapsed, 1.0, "laying out one log must not cost a second")
    }

    /// The layout is a stored snapshot, not a computed property. A `LazyVStack` asks its rows for
    /// their content constantly while scrolling, and recomputing the series on every one of those
    /// reads would rebuild a thousand-entry chart per frame.
    func testTheLayoutIsHeldRatherThanRecomputedOnEveryRead() async {
        let viewModel = WaterfallViewModel(requests: log(of: 10), totalCount: 10)
        await viewModel.recompute()
        let first = viewModel.layout.rows
        viewModel.update(requests: log(of: 20), totalCount: 20)
        XCTAssertEqual(viewModel.layout.rows.map(\.id), first.map(\.id),
                       "reading rows must not lay the log out again")
        await viewModel.recompute()
        XCTAssertEqual(viewModel.layout.rows.count, 20, "recomputation is the only thing that replaces them")
    }

    /// Every row is built once, in the same pass, rather than each row looking its own request up
    /// by walking the log — which is the quadratic shape this page invites.
    func testEveryRowIsMatchedToItsRequestInTheSamePass() {
        let requests = log(of: 200)
        let layout = WaterfallViewModel.layout(of: requests, limit: requests.count)
        XCTAssertEqual(layout.rows.count, 200)
        XCTAssertEqual(Set(layout.rows.map(\.id)).count, 200, "no request is drawn twice")
        XCTAssertTrue(layout.rows.first?.request === requests.first)
    }
}
