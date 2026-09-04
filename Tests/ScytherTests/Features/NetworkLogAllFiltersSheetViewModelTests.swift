//
//  NetworkLogAllFiltersSheetViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkLogAllFiltersSheetViewModelTests: XCTestCase {

    private func makeViewModel(
        filter: NetworkLogFilter = NetworkLogFilter(),
        onChange: @escaping (NetworkLogFilter) -> Void = { _ in }
    ) -> NetworkLogAllFiltersSheetViewModel {
        NetworkLogAllFiltersSheetViewModel(
            filter: filter,
            options: { dimension in
                switch dimension {
                case .method: return [NetworkLogFilterOption(id: "GET", title: "GET")]
                case .host: return [NetworkLogFilterOption(id: "a.com", title: "a.com")]
                case .statusCode: return [NetworkLogFilterOption(id: "200", title: "200")]
                default: return NetworkLogFilterOption.staticOptions(for: dimension)
                }
            },
            onChange: onChange
        )
    }

    func testSectionsCoverEveryDimensionInOrder() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.sections.map(\.dimension), NetworkLogFilterDimension.allCases)
        XCTAssertEqual(viewModel.sections.first?.options.map(\.id), ["GET"])
    }

    func testGroupedSectionsFollowGroupOrder() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.groups.map(\.group), NetworkLogFilterGroup.allCases)
        XCTAssertEqual(viewModel.groups.first?.sections.map(\.dimension), [.method, .host, .api, .graphQL])
    }

    func testToggleUpdatesFilterAndNotifies() {
        var received: NetworkLogFilter?
        let viewModel = makeViewModel { received = $0 }
        let option = NetworkLogFilterOption(id: HTTPStatusClass.success.rawValue, title: "2xx")

        viewModel.toggle(option, in: .status)
        XCTAssertTrue(viewModel.isSelected(option, in: .status))
        XCTAssertEqual(received?.statusClasses, [.success])
        XCTAssertTrue(viewModel.canReset)

        viewModel.toggle(option, in: .status)
        XCTAssertFalse(viewModel.isSelected(option, in: .status))
        XCTAssertEqual(received?.statusClasses, [])
        XCTAssertFalse(viewModel.canReset)
    }

    func testSummaryIsAnyWhenUnselectedAndJoinsTitlesInOptionOrder() {
        var initial = NetworkLogFilter()
        initial.statusClasses = [.serverError, .success]
        let viewModel = makeViewModel(filter: initial)

        XCTAssertEqual(viewModel.summary(for: .method), "Any")
        XCTAssertEqual(viewModel.summary(for: .status), "2xx Success, 5xx Server Error")
    }

    func testHostModeChangesNotifyAndAffectSummary() {
        var initial = NetworkLogFilter()
        initial.hosts = ["a.com"]
        var received: NetworkLogFilter?
        let viewModel = makeViewModel(filter: initial) { received = $0 }

        XCTAssertEqual(viewModel.summary(for: .host), "a.com")
        viewModel.setHostMode(.exclude)
        XCTAssertEqual(received?.hostMode, .exclude)
        XCTAssertEqual(viewModel.summary(for: .host), "Exclude: a.com")

        viewModel.reset(.host)
        XCTAssertEqual(received?.hostMode, .include)
        XCTAssertEqual(viewModel.summary(for: .host), "Any")
    }

    func testResetForSingleDimensionLeavesOthersIntact() {
        var initial = NetworkLogFilter()
        initial.methods = ["GET"]
        initial.hosts = ["a.com"]
        var received: NetworkLogFilter?
        let viewModel = makeViewModel(filter: initial) { received = $0 }

        XCTAssertTrue(viewModel.canReset(.method))
        XCTAssertFalse(viewModel.canReset(.status))

        viewModel.reset(.method)
        XCTAssertFalse(viewModel.canReset(.method))
        XCTAssertEqual(received?.methods, [])
        XCTAssertEqual(received?.hosts, ["a.com"])
    }

    func testSingleSelectDimensionReplacesSelectionOnToggle() {
        var received: NetworkLogFilter?
        let viewModel = makeViewModel { received = $0 }
        let minute = NetworkLogFilterOption(id: RecencyWindow.lastMinute.rawValue, title: "Last minute")
        let hour = NetworkLogFilterOption(id: RecencyWindow.lastHour.rawValue, title: "Last hour")

        viewModel.toggle(minute, in: .recency)
        viewModel.toggle(hour, in: .recency)
        XCTAssertFalse(viewModel.isSelected(minute, in: .recency))
        XCTAssertTrue(viewModel.isSelected(hour, in: .recency))
        XCTAssertEqual(received?.recencyWindow, .lastHour)

        viewModel.toggle(hour, in: .recency)
        XCTAssertNil(received?.recencyWindow)
    }

    func testResetClearsEveryDimensionAndNotifies() {
        var initial = NetworkLogFilter()
        initial.methods = ["GET"]
        initial.recencyWindow = .lastHour
        var received: NetworkLogFilter?
        let viewModel = makeViewModel(filter: initial) { received = $0 }
        XCTAssertTrue(viewModel.canReset)

        viewModel.reset()
        XCTAssertFalse(viewModel.canReset)
        XCTAssertEqual(received, NetworkLogFilter())
    }
}
