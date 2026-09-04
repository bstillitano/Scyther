//
//  NetworkLogFilterSheetViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkLogFilterSheetViewModelTests: XCTestCase {

    private let options = [
        NetworkLogFilterOption(id: "GET", title: "GET"),
        NetworkLogFilterOption(id: "POST", title: "POST"),
        NetworkLogFilterOption(id: "DELETE", title: "DELETE"),
    ]

    private func makeViewModel(
        selected: Set<String> = [],
        onChange: @escaping (Set<String>) -> Void = { _ in }
    ) -> NetworkLogFilterSheetViewModel {
        NetworkLogFilterSheetViewModel(
            dimension: .method,
            options: options,
            selected: selected,
            onChange: onChange
        )
    }

    func testToggleAddsAndRemovesSelectionAndNotifies() {
        var received: [Set<String>] = []
        let viewModel = makeViewModel { received.append($0) }

        viewModel.toggle(options[0])
        XCTAssertTrue(viewModel.isSelected(options[0]))
        XCTAssertEqual(received.last, ["GET"])

        viewModel.toggle(options[0])
        XCTAssertFalse(viewModel.isSelected(options[0]))
        XCTAssertEqual(received.last, [])
    }

    func testResetClearsSelectionAndNotifies() {
        var received: Set<String>?
        let viewModel = makeViewModel(selected: ["GET", "POST"]) { received = $0 }
        XCTAssertTrue(viewModel.canReset)
        viewModel.reset()
        XCTAssertFalse(viewModel.canReset)
        XCTAssertEqual(viewModel.selectedCount, 0)
        XCTAssertEqual(received, [])
    }

    func testCanResetTracksSelection() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.canReset)
        viewModel.toggle(options[2])
        XCTAssertTrue(viewModel.canReset)
        viewModel.toggle(options[2])
        XCTAssertFalse(viewModel.canReset)
    }

    func testHostSheetSupportsModeAndNotifiesChanges() {
        var received: HostFilterMode?
        let viewModel = NetworkLogFilterSheetViewModel(
            dimension: .host,
            options: [NetworkLogFilterOption(id: "a.com", title: "a.com")],
            selected: [],
            hostMode: .include,
            onChange: { _ in },
            onHostModeChange: { received = $0 }
        )
        XCTAssertTrue(viewModel.supportsHostMode)
        viewModel.setHostMode(.exclude)
        XCTAssertEqual(viewModel.hostMode, .exclude)
        XCTAssertEqual(received, .exclude)
    }

    func testNonHostSheetDoesNotSupportMode() {
        XCTAssertFalse(makeViewModel().supportsHostMode)
    }

    func testSingleSelectSheetReplacesSelectionOnToggle() {
        var received: Set<String>?
        let minute = NetworkLogFilterOption(id: RecencyWindow.lastMinute.rawValue, title: "Last minute")
        let hour = NetworkLogFilterOption(id: RecencyWindow.lastHour.rawValue, title: "Last hour")
        let viewModel = NetworkLogFilterSheetViewModel(
            dimension: .recency,
            options: [minute, hour],
            selected: [],
            onChange: { received = $0 }
        )

        viewModel.toggle(minute)
        viewModel.toggle(hour)
        XCTAssertEqual(received, [hour.id])
        XCTAssertFalse(viewModel.isSelected(minute))

        viewModel.toggle(hour)
        XCTAssertEqual(received, [])
    }

    func testInitialSelectionIsHonoured() {
        let viewModel = makeViewModel(selected: ["POST"])
        XCTAssertTrue(viewModel.isSelected(options[1]))
        XCTAssertFalse(viewModel.isSelected(options[0]))
        XCTAssertEqual(viewModel.selectedCount, 1)
        XCTAssertEqual(viewModel.title, "Method")
    }
}
