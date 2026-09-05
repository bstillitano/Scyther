//
//  BreakpointsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class BreakpointsViewModelTests: XCTestCase {

    /// Declared `nonisolated(unsafe)` because `setUpWithError()` and `tearDownWithError()` are
    /// inherited as nonisolated. XCTest runs them on the same thread as the test body, so the
    /// access is serialised even though the compiler cannot prove it.
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "BreakpointsViewModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        BreakpointSnapshot.update(isEnabled: false, breakpoints: [])
    }

    private func makeStore() -> BreakpointStore {
        BreakpointStore(defaults: defaults)
    }

    private func makeBreakpoint(_ name: String,
                                stage: NetworkBreakpoint.Stage = .request,
                                timeout: TimeInterval = 60) -> NetworkBreakpoint {
        NetworkBreakpoint(name: name, match: .path("/v1/*"), stage: stage, timeout: timeout)
    }

    func testTheListMirrorsTheStore() {
        let store = makeStore()
        let viewModel = BreakpointsViewModel(store: store)
        XCTAssertTrue(viewModel.isEmpty)

        store.add(makeBreakpoint("cart"))

        XCTAssertEqual(viewModel.breakpoints.map(\.name), ["cart"])
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testTheMasterSwitchReadsAndWritesTheStore() {
        let store = makeStore()
        let viewModel = BreakpointsViewModel(store: store)
        XCTAssertFalse(viewModel.isEnabled)

        viewModel.isEnabled = true

        XCTAssertTrue(store.isEnabled)
    }

    func testTheSubtitleNamesTheStageAndTheTimeout() {
        let viewModel = BreakpointsViewModel(store: makeStore())
        let subtitle = viewModel.subtitle(for: makeBreakpoint("cart", stage: .response, timeout: 30))
        XCTAssertTrue(subtitle.contains(NetworkBreakpoint.Stage.response.title))
        XCTAssertTrue(subtitle.contains(NetworkBreakpoint.secondsText(30)))
    }

    func testEnablingARowWritesThrough() {
        let store = makeStore()
        var breakpoint = makeBreakpoint("cart")
        breakpoint.isEnabled = false
        store.add(breakpoint)
        let viewModel = BreakpointsViewModel(store: store)

        viewModel.setEnabled(breakpoint, to: true)

        XCTAssertEqual(store.breakpoints.first?.isEnabled, true)
    }

    func testDeletionIsConfirmedBeforeAnythingIsRemoved() {
        let store = makeStore()
        let breakpoint = makeBreakpoint("cart")
        store.add(breakpoint)
        let viewModel = BreakpointsViewModel(store: store)

        viewModel.requestDeletion(of: breakpoint)
        XCTAssertEqual(viewModel.pendingDeletions.map(\.name), ["cart"])
        XCTAssertEqual(store.breakpoints.count, 1, "nothing goes until it is confirmed")

        viewModel.confirmDeletion()
        XCTAssertTrue(store.breakpoints.isEmpty)
        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
    }

    func testCancellingADeletionKeepsEverything() {
        let store = makeStore()
        store.add(makeBreakpoint("cart"))
        let viewModel = BreakpointsViewModel(store: store)

        viewModel.requestDeletion(at: IndexSet(integer: 0))
        viewModel.cancelDeletion()

        XCTAssertEqual(store.breakpoints.count, 1)
        XCTAssertTrue(viewModel.pendingDeletions.isEmpty)
    }

    /// Edit mode deletes several rows in one gesture, and taking only the first offset would
    /// silently keep the rest.
    func testASweptDeletionKeepsEveryOffset() {
        let store = makeStore()
        store.add(makeBreakpoint("one"))
        store.add(makeBreakpoint("two"))
        store.add(makeBreakpoint("three"))
        let viewModel = BreakpointsViewModel(store: store)

        viewModel.requestDeletion(at: IndexSet([0, 2]))
        viewModel.confirmDeletion()

        XCTAssertEqual(store.breakpoints.map(\.name), ["two"])
    }
}

@MainActor
final class BreakpointEditorViewModelTests: XCTestCase {

    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "BreakpointEditorViewModelTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        BreakpointSnapshot.update(isEnabled: false, breakpoints: [])
    }

    private func makeStore() -> BreakpointStore {
        BreakpointStore(defaults: defaults)
    }

    func testANewBreakpointIsNotValidUntilItIsNamedAndNarrowed() {
        let viewModel = BreakpointEditorViewModel(breakpoint: nil, store: makeStore())
        XCTAssertFalse(viewModel.isValid, "an unnamed breakpoint is indistinguishable from any other")

        viewModel.draft.name = "cart"
        XCTAssertFalse(viewModel.isValid, "and one with no facets would hold every request the app makes")

        viewModel.pathText = "/v1/cart"
        XCTAssertTrue(viewModel.isValid)
    }

    /// A match of nothing but `*` constrains exactly as much as an empty one, and holding every
    /// request the app makes for a minute each is the worst thing this feature can do.
    func testAMatchThatMatchesEverythingIsRefused() {
        let viewModel = BreakpointEditorViewModel(breakpoint: nil, store: makeStore())
        viewModel.draft.name = "everything"
        viewModel.pathKind = .wildcard
        viewModel.pathText = "*"
        XCTAssertFalse(viewModel.isValid)
    }

    func testSavingANewBreakpointAddsIt() {
        let store = makeStore()
        let viewModel = BreakpointEditorViewModel(breakpoint: nil, store: store)
        viewModel.draft.name = "  cart  "
        viewModel.hostText = "api.example.com"
        viewModel.draft.stage = .both

        XCTAssertTrue(viewModel.save())
        XCTAssertEqual(store.breakpoints.map(\.name), ["cart"], "the name is trimmed on the way in")
        XCTAssertEqual(store.breakpoints.first?.stage, .both)
    }

    func testSavingAnEditedBreakpointUpdatesItInPlace() {
        let store = makeStore()
        let breakpoint = NetworkBreakpoint(name: "cart", match: .path("/v1/cart"))
        store.add(breakpoint)
        store.add(NetworkBreakpoint(name: "checkout", match: .path("/v1/checkout")))

        let viewModel = BreakpointEditorViewModel(breakpoint: breakpoint, store: store)
        viewModel.draft.name = "renamed"
        XCTAssertTrue(viewModel.save())

        XCTAssertEqual(store.breakpoints.map(\.name), ["renamed", "checkout"])
    }

    func testEmptyingAPatternRemovesTheFacetEntirely() {
        let viewModel = BreakpointEditorViewModel(breakpoint: nil, store: makeStore())
        viewModel.hostText = "api.example.com"
        XCTAssertNotNil(viewModel.draft.match.host)

        viewModel.hostText = "   "
        XCTAssertNil(viewModel.draft.match.host, "a blank field places no constraint")
    }

    func testAPatternKindIsRememberedWhileTheFieldIsEmpty() {
        let viewModel = BreakpointEditorViewModel(breakpoint: nil, store: makeStore())
        viewModel.pathKind = .wildcard
        XCTAssertNil(viewModel.draft.match.path)

        viewModel.pathText = "/v1/*"
        XCTAssertEqual(viewModel.draft.match.path?.kind, .wildcard)
    }

    func testTheTimeoutIsClampedAsItIsTyped() {
        let viewModel = BreakpointEditorViewModel(breakpoint: nil, store: makeStore())
        viewModel.timeout = 1
        XCTAssertEqual(viewModel.timeout, NetworkBreakpoint.timeoutRange.lowerBound)

        viewModel.timeout = 10_000
        XCTAssertEqual(viewModel.timeout, NetworkBreakpoint.timeoutRange.upperBound)
    }

    func testMethodsToggleAndSummarise() {
        let viewModel = BreakpointEditorViewModel(breakpoint: nil, store: makeStore())
        XCTAssertEqual(viewModel.methodsSummary, localized("Any method"))

        viewModel.toggle(method: "POST")
        viewModel.toggle(method: "GET")
        XCTAssertTrue(viewModel.isSelected(method: "GET"))
        XCTAssertEqual(viewModel.methodsSummary, "GET, POST", "listed in the checklist's order")

        viewModel.toggle(method: "GET")
        XCTAssertEqual(viewModel.methodsSummary, "POST")
    }

    func testTheTitleSaysWhetherItIsCreatingOrEditing() {
        let store = makeStore()
        XCTAssertEqual(BreakpointEditorViewModel(breakpoint: nil, store: store).title,
                       localized("New Breakpoint"))
        XCTAssertEqual(
            BreakpointEditorViewModel(breakpoint: NetworkBreakpoint(name: "cart", match: .path("/v1")),
                                      store: store).title,
            localized("Edit Breakpoint")
        )
    }
}
