//
//  PseudoLocalizationViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

/// Covers the relaunch alert the Right to Left switch raises.
///
/// Right to Left takes effect only when the process next starts, so a developer who flicks it and
/// sees nothing move has been told nothing at all. The alert is the whole of that explanation, and
/// these tests pin the one thing about it that can be got wrong quietly: *when* it is raised.
@MainActor
final class PseudoLocalizationViewModelTests: XCTestCase {

    /// The view model writes through to the shared singleton, which is backed by the developer's
    /// own settings suite. Restored afterwards so running the suite does not switch a mode on or
    /// off behind their back.
    private var restore: Bool = false

    override func setUp() {
        super.setUp()
        restore = PseudoLocalization.instance.rightToLeft
    }

    override func tearDown() {
        PseudoLocalization.instance.rightToLeft = restore
        super.tearDown()
    }

    func testSwitchingRightToLeftOnRaisesTheRelaunchAlert() {
        let viewModel = PseudoLocalizationViewModel()
        viewModel.rightToLeft = true
        XCTAssertTrue(viewModel.showingRelaunchAlert)
    }

    /// Both directions, unlike the language page's alert. Switching off is just as invisible as
    /// switching on: the keys go immediately and the running process keeps the direction it
    /// launched with.
    func testSwitchingRightToLeftOffRaisesTheRelaunchAlertToo() {
        let viewModel = PseudoLocalizationViewModel()
        viewModel.rightToLeft = true
        viewModel.showingRelaunchAlert = false
        viewModel.rightToLeft = false
        XCTAssertTrue(viewModel.showingRelaunchAlert)
    }

    func testATextModeDoesNotRaiseTheRelaunchAlert() {
        let viewModel = PseudoLocalizationViewModel()
        viewModel.accented = true
        viewModel.lengthened = true
        viewModel.showsKeys = true
        viewModel.showsBoundaries = false
        XCTAssertFalse(viewModel.showingRelaunchAlert)
    }

    /// Turning everything off is the other way to switch right-to-left off, and the one most
    /// likely to be reached by someone trying to put things back.
    func testTurningEverythingOffRaisesTheAlertWhenRightToLeftWasOn() {
        let viewModel = PseudoLocalizationViewModel()
        viewModel.rightToLeft = true
        viewModel.showingRelaunchAlert = false
        viewModel.turnEverythingOff()
        XCTAssertTrue(viewModel.showingRelaunchAlert)
    }

    func testTurningEverythingOffIsSilentWhenRightToLeftWasAlreadyOff() {
        let viewModel = PseudoLocalizationViewModel()
        viewModel.rightToLeft = false
        viewModel.showingRelaunchAlert = false
        viewModel.turnEverythingOff()
        XCTAssertFalse(viewModel.showingRelaunchAlert)
    }
}
#endif
