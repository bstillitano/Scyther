//
//  BreakpointPresenterTests.swift
//  ScytherTests
//

@testable import Scyther
import UIKit
import XCTest

@MainActor
final class BreakpointPresenterTests: XCTestCase {

    /// Records what a continuation was handed.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [BreakpointResolution] = []

        var resume: @Sendable (BreakpointResolution) -> Void {
            { [self] resolution in lock.withLock { storage.append(resolution) } }
        }

        var resolutions: [BreakpointResolution] { lock.withLock { storage } }
    }

    /// Counts the presentations a presenter asked for, without touching UIKit.
    ///
    /// Lock-guarded and `@unchecked Sendable` so the counters can be written from the presenter's
    /// hooks and read from a test body without the compiler having to prove which actor each side
    /// is on.
    private final class PresentationLog: @unchecked Sendable {
        private let lock = NSLock()
        private var presentations = 0
        private var dismissals = 0

        /// How many times the editor was asked to be presented.
        var presented: Int { lock.withLock { presentations } }

        /// How many times it was asked to be dismissed.
        var dismissed: Int { lock.withLock { dismissals } }

        /// Records a presentation.
        func recordPresentation() { lock.withLock { presentations += 1 } }

        /// Records a dismissal.
        func recordDismissal() { lock.withLock { dismissals += 1 } }
    }

    private var coordinator: BreakpointCoordinator!
    private var presenter: BreakpointPresenter!
    private var log: PresentationLog!

    override func setUp() {
        super.setUp()
        coordinator = BreakpointCoordinator()
        presenter = BreakpointPresenter(coordinator: coordinator)
        let log = PresentationLog()
        self.log = log
        presenter.presentEditor = { _ in log.recordPresentation() }
        presenter.dismissEditor = { _ in log.recordDismissal() }
        presenter.applicationState = { .active }
        presenter.start()
    }

    override func tearDown() {
        presenter = nil
        coordinator = nil
        log = nil
        super.tearDown()
    }

    @discardableResult
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func draft() -> BreakpointDraft {
        BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/v1/users")!))
    }

    @discardableResult
    private func hold(_ recorder: Recorder = Recorder(), name: String = "cart") -> UUID {
        coordinator.pause(draft(), name: name, stage: .request, timeout: 60, resume: recorder.resume)
    }

    func testTheFirstHeldExchangePutsTheEditorOnScreen() {
        hold()

        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        XCTAssertEqual(log.presented, 1)
    }

    /// A second held request joins the screen that is already up rather than presenting over it.
    func testASecondHeldExchangeDoesNotPresentAgain() {
        hold(name: "cart")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })

        hold(name: "checkout")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 2 })
        XCTAssertEqual(log.presented, 1)
    }

    func testTheEditorIsDismissedOnceNothingIsHeld() throws {
        hold()
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })

        let id = try XCTUnwrap(presenter.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)

        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })
        XCTAssertEqual(log.dismissed, 1)
    }

    /// A held request the developer cannot see is indistinguishable from a hang, and the developer
    /// is by definition not looking at a backgrounded app.
    func testAPauseTakenWhileBackgroundedIsSkippedAndResumedUnchanged() throws {
        presenter.applicationState = { .background }
        let recorder = Recorder()
        hold(recorder)

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .continue(let resumed) = try XCTUnwrap(recorder.resolutions.first) else {
            return XCTFail("expected the exchange to be let go unchanged")
        }
        XCTAssertEqual(resumed, draft())
        XCTAssertEqual(log.presented, 0, "nothing is presented over an app nobody is looking at")
        XCTAssertTrue(presenter.pending.isEmpty)
    }

    func testTheEditorCanBePresentedAgainAfterItHasBeenDismissed() throws {
        hold()
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        let id = try XCTUnwrap(presenter.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)
        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })

        hold()

        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        XCTAssertEqual(log.presented, 2)
    }

    /// `start()` is called from `Scyther.start()`, which a host app may call more than once.
    func testStartingTwiceLeavesOneSubscriber() {
        presenter.start()
        presenter.start()

        hold()

        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        XCTAssertEqual(log.presented, 1)
    }
}
