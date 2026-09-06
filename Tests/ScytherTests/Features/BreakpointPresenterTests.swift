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
        private var outcomes: [Bool] = []

        /// How many times the editor was asked to be presented.
        var presented: Int { lock.withLock { presentations } }

        /// How many times it was asked to be dismissed.
        var dismissed: Int { lock.withLock { dismissals } }

        /// The outcome each presentation is to report, oldest first. Anything past the end
        /// succeeds.
        func willReport(_ outcomes: [Bool]) { lock.withLock { self.outcomes = outcomes } }

        /// Records a presentation and reports whether it reached the screen.
        @discardableResult
        func recordPresentation() -> Bool {
            lock.withLock {
                let outcome = presentations < outcomes.count ? outcomes[presentations] : true
                presentations += 1
                return outcome
            }
        }

        /// Records a dismissal.
        func recordDismissal() { lock.withLock { dismissals += 1 } }
    }

    /// Holds the "that animation has finished" callbacks, so a test can decide when — or whether —
    /// a presentation or a dismissal completes.
    ///
    /// Main-actor isolated, like everything it stands in for: the presenter hands these callbacks
    /// out and calls them back on the main actor, so no lock is needed here.
    @MainActor
    private final class Animations {
        /// Whether callbacks are held rather than run as they arrive. `false` animates instantly,
        /// which is what every test that is not about the animations wants.
        var isDeferring = false

        private var held: [() -> Void] = []

        /// Takes one animation's callback.
        func record(_ completion: @escaping () -> Void) {
            guard isDeferring else { return completion() }
            held.append(completion)
        }

        /// Ends every animation in flight.
        func finish() {
            let all = held
            held = []
            all.forEach { $0() }
        }
    }

    /// A started presenter over a coordinator of its own, with its UIKit hooks recorded.
    ///
    /// Sendable — every member is either lock-guarded or main-actor isolated — so it can be
    /// carried out of ``makeFixture()`` and into the inherited-nonisolated `setUp()`.
    private struct Fixture: Sendable {
        let coordinator: BreakpointCoordinator
        let presenter: BreakpointPresenter
        let log: PresentationLog
        let appearances: Animations
        let dismissals: Animations
        let retries: Animations
    }

    /// Builds and starts a presenter. Static, so nothing about the test case is captured.
    @MainActor
    private static func makeFixture() -> Fixture {
        let coordinator = BreakpointCoordinator()
        let presenter = BreakpointPresenter(coordinator: coordinator)
        let log = PresentationLog()
        let appearances = Animations()
        let dismissals = Animations()
        // Retries are always held: a test that cares runs them by hand, and one that does not is
        // spared a presenter that keeps trying in the background while it makes its assertions.
        let retries = Animations()
        retries.isDeferring = true
        presenter.scheduleRetry = { work in retries.record(work) }
        presenter.presentEditor = { _, appeared in
            let didPresent = log.recordPresentation()
            if didPresent { appearances.record(appeared) }
            return didPresent
        }
        presenter.dismissEditor = { _, gone in
            log.recordDismissal()
            dismissals.record(gone)
        }
        presenter.applicationState = { .active }
        presenter.start()
        return Fixture(
            coordinator: coordinator,
            presenter: presenter,
            log: log,
            appearances: appearances,
            dismissals: dismissals,
            retries: retries
        )
    }

    /// Declared `nonisolated(unsafe)` because `setUp()` and `tearDown()` are inherited
    /// nonisolated. XCTest runs them on the same thread as the test body, so the access is
    /// serialised even though the compiler cannot prove it — the pattern the store suites in this
    /// target already use.
    nonisolated(unsafe) private var fixture: Fixture!

    private var coordinator: BreakpointCoordinator { fixture.coordinator }
    private var presenter: BreakpointPresenter { fixture.presenter }
    private var log: PresentationLog { fixture.log }
    private var appearances: Animations { fixture.appearances }
    private var dismissals: Animations { fixture.dismissals }
    private var retries: Animations { fixture.retries }

    /// Builds the fixture on the main actor, which is where XCTest runs a synchronous test body
    /// of a `@MainActor` suite. `makeFixture()` is static, so no part of the test case crosses
    /// the isolation boundary.
    override func setUp() {
        super.setUp()
        fixture = MainActor.assumeIsolated { Self.makeFixture() }
    }

    override func tearDown() {
        fixture = nil
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

    /// The screen has no manual exit while anything is held, so if the presenter's belief about
    /// what is on screen ever diverges from UIKit's, an empty modal over an app that is waiting
    /// for nothing is a dead end. Dismissal therefore keys on there being a controller, not on
    /// the flag.
    func testTheEditorIsDismissedEvenIfThePresenterNoLongerBelievesItPresented() throws {
        hold()
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })

        presenter.forgetPresentationForTesting()

        let id = try XCTUnwrap(presenter.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)

        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })
        XCTAssertEqual(log.dismissed, 1, "the screen has to come down even when the flag says it is not up")
    }

    /// UIKit drops a dismissal asked for while the presentation is still animating, and says
    /// nothing about having done so. A short timeout, or a developer quicker than the animation,
    /// resolves the exchange inside that window — and the dropped dismissal left an empty modal
    /// over an app waiting for nothing, with no way out, which is exactly what this screen must
    /// never be.
    func testADismissalAskedForWhileTheEditorIsAppearingHappensOnceItHas() throws {
        appearances.isDeferring = true
        hold()
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })

        let id = try XCTUnwrap(presenter.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)
        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })
        XCTAssertEqual(log.dismissed, 0, "UIKit would ignore this one, so it is not asked for yet")

        appearances.finish()

        XCTAssertEqual(log.dismissed, 1, "it is owed, and paid once the animation ends")
    }

    /// Unless something is held again first, in which case the screen is wanted after all.
    func testAnExchangeHeldWhileADismissalIsOwedKeepsTheScreenUp() throws {
        appearances.isDeferring = true
        hold(name: "cart")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        let id = try XCTUnwrap(presenter.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)
        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })

        hold(name: "checkout")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        appearances.finish()

        XCTAssertEqual(log.dismissed, 0, "the app is waiting on something again")
        XCTAssertEqual(log.presented, 1, "and the screen it is waiting behind never left")
    }

    /// UIKit accepts a presentation over a controller that is still leaving, and then shows
    /// nothing at all. An exchange held in that moment — the developer continues one request and
    /// makes the next straight away — sat behind a screen nobody could see while the app waited
    /// out the whole timeout.
    func testAnExchangeHeldWhileTheScreenIsLeavingIsShownOnceItHasGone() throws {
        dismissals.isDeferring = true
        hold(name: "cart")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        let id = try XCTUnwrap(presenter.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)
        XCTAssertTrue(waitUntil { self.log.dismissed == 1 })

        hold(name: "checkout")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        XCTAssertEqual(log.presented, 1, "nothing is presented over a screen that is on its way out")

        dismissals.finish()

        XCTAssertEqual(log.presented, 2, "and the wait ends when it has gone")
    }

    /// The escape hatch behind the empty list's close button.
    func testDismissingByHandTakesTheScreenDown() {
        hold()
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })

        presenter.dismiss()

        XCTAssertEqual(log.dismissed, 1)
    }

    /// A held request the developer cannot see is indistinguishable from a hang, and the developer
    /// is by definition not looking at an app that is not on screen.
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

    // MARK: - A presentation that did not happen

    /// The flag used to record the intention to present rather than the outcome of presenting. A
    /// presentation UIKit refuses — no key window, or an anchor part-way through dismissing the
    /// last editor — then left it stuck true, and every hold after it was published to a screen
    /// that was never there while the app sat paused for up to five minutes.
    func testAPresentationThatDidNotHappenIsOfferedAgainOnTheNextHold() throws {
        log.willReport([false])

        let firstRecorder = Recorder()
        hold(firstRecorder, name: "cart")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        XCTAssertEqual(log.presented, 1, "it was tried")

        hold(name: "checkout")

        XCTAssertTrue(waitUntil { self.presenter.pending.count == 2 })
        XCTAssertTrue(waitUntil { self.log.presented == 2 },
                      "a refused presentation must be offered again rather than swallowed")
        XCTAssertTrue(firstRecorder.resolutions.isEmpty, "and the first exchange is still held")
    }

    /// A refusal is momentary — the anchor is a sheet on its way out, or a screen on its way in —
    /// and the app is paused behind it. Waiting for the next hold meant a replayed request that
    /// was held while its own editor was dismissing sat invisible for the whole of its timeout.
    func testARefusedPresentationIsTriedAgainWhileTheExchangeIsHeld() {
        log.willReport([false])

        hold()
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        XCTAssertEqual(log.presented, 1, "it was tried")

        retries.finish()

        XCTAssertEqual(log.presented, 2, "and tried again, without waiting for another hold")
    }

    /// Nothing is booked once the exchange has gone: the retry is for a paused app, and an app
    /// that is not paused has nothing to show.
    func testNoRetryIsBookedOnceNothingIsHeld() throws {
        log.willReport([false])

        hold()
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        let id = try XCTUnwrap(presenter.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)
        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })

        retries.finish()

        XCTAssertEqual(log.presented, 1, "there is nothing left to present")
    }

    /// Once one succeeds, the editor is on screen and further holds join it.
    func testAPresentationThatSucceededAfterAFailureIsNotRepeated() {
        log.willReport([false, true])

        hold(name: "cart")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })
        hold(name: "checkout")
        XCTAssertTrue(waitUntil { self.log.presented == 2 })

        hold(name: "search")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 3 })
        XCTAssertEqual(log.presented, 2, "the second presentation took, so there is nothing to retry")
    }

    // MARK: - Leaving the screen

    /// Pulling down Control Centre makes the app `.inactive`. The skip used to resolve the whole
    /// pending list whenever it ran, so a glance at Control Centre while a request was being
    /// edited discarded the edits and dismissed the editor.
    func testAPauseTakenWhileInactiveDoesNotDiscardWhatIsAlreadyHeld() throws {
        let beingEdited = Recorder()
        hold(beingEdited, name: "cart")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })

        presenter.applicationState = { .inactive }
        let arrivingLate = Recorder()
        hold(arrivingLate, name: "checkout")

        XCTAssertTrue(waitUntil { arrivingLate.resolutions.count == 1 },
                      "the new pause is the one that is skipped")
        XCTAssertTrue(beingEdited.resolutions.isEmpty,
                      "the exchange the developer is editing must survive Control Centre")
        XCTAssertEqual(presenter.pending.map(\.breakpointName), ["cart"])
        XCTAssertEqual(log.dismissed, 0, "and the editor stays where it is")
    }

    /// The app's state used to be sampled only when the coordinator's list changed, so one
    /// exchange held a moment before the developer switched away sat there, invisible, for the
    /// whole of its timeout.
    func testBackgroundingReleasesAnExchangeThatWasAlreadyHeld() throws {
        let recorder = Recorder()
        hold(recorder, name: "cart")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 1 })

        presenter.applicationState = { .background }
        presenter.applicationDidEnterBackground()

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .continue(let resumed) = try XCTUnwrap(recorder.resolutions.first) else {
            return XCTFail("expected the exchange to be let go unchanged")
        }
        XCTAssertEqual(resumed, draft(), "unchanged means unchanged")
        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })
        XCTAssertEqual(log.dismissed, 1)
    }

    /// Every exchange goes, however many there are, and each of them exactly once.
    func testBackgroundingReleasesEveryExchangeExactlyOnce() {
        let first = Recorder()
        let second = Recorder()
        hold(first, name: "cart")
        hold(second, name: "checkout")
        XCTAssertTrue(waitUntil { self.presenter.pending.count == 2 })

        presenter.applicationState = { .background }
        presenter.applicationDidEnterBackground()

        XCTAssertTrue(waitUntil { first.resolutions.count == 1 && second.resolutions.count == 1 })
        XCTAssertTrue(waitUntil { self.presenter.pending.isEmpty })
        XCTAssertEqual(first.resolutions.count, 1)
        XCTAssertEqual(second.resolutions.count, 1)
    }

    /// Nothing held, nothing to let go of — and no log line about it either.
    func testBackgroundingWithNothingHeldDoesNothing() {
        presenter.applicationState = { .background }
        presenter.applicationDidEnterBackground()

        XCTAssertTrue(presenter.pending.isEmpty)
        XCTAssertEqual(log.dismissed, 0)
    }
}
