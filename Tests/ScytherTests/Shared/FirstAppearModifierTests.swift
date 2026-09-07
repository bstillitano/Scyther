//
//  FirstAppearModifierTests.swift
//  ScytherTests
//

@testable import Scyther
import SwiftUI
import XCTest

/// Lets a test hold a first-appear action open, and counts what happened.
///
/// The wait is a continuation rather than a polling loop on purpose. SwiftUI cancels the `task`
/// belonging to a view it has discarded, and a loop built out of `try? await Task.sleep` spins at
/// full speed once cancelled — on the main actor, which is where the run loop the test is pumping
/// lives. A continuation is simply never resumed until the test says so, cancelled or not, which
/// is also a fair model of the real thing: `NetworkHelper.ipAddress` does not check for
/// cancellation either, which is exactly why the discarded menu's fetch stayed in flight.
@MainActor
private final class FirstAppearRecorder {
    /// How many times an action has been started.
    private(set) var started = 0

    /// How many times one has run to completion.
    private(set) var finished = 0

    /// Everyone currently waiting to be let go.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Whether the gate is already open, so a later action does not wait at all.
    private var isOpen = false

    /// Every model a completed action loaded, in order.
    private(set) var loaded: [FirstAppearModifierTests.ProbeModel] = []

    /// Records that `model` was loaded by an action that ran to completion.
    ///
    /// - Parameter model: The model the finishing action populated.
    func record(_ model: FirstAppearModifierTests.ProbeModel) {
        loaded.append(model)
    }

    /// Records a start and waits for ``release()``.
    func begin() async {
        started += 1
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        finished += 1
    }

    /// Lets everyone waiting through, and everyone who arrives afterwards.
    func release() {
        isOpen = true
        let resuming = waiting
        waiting.removeAll()
        resuming.forEach { $0.resume() }
    }
}

/// `onFirstAppear` against a real hosted view hierarchy.
///
/// Hosted rather than unit-tested, because the defect is entirely about what SwiftUI does to the
/// view: the guard was a `@State` flag, `@State` belongs to the view, and SwiftUI is free to throw
/// a view away and build a new one — which starts with the flag back at `false` and runs the
/// action again while the first call is still suspended.
///
/// Presenting anything over Scyther's menu did exactly that. The menu's first-appear fetched the
/// device's IP address, a breakpoint held the fetch, holding it presented an editor, presenting
/// the editor re-created the menu, and round it went once a second until ten modals were stacked
/// over the one screen that could have switched the breakpoint off.
///
/// The re-creation is reproduced by changing the subtree's `id`, which is SwiftUI's own way of
/// saying "this is a different view now" — the same effect as the presentation, without needing a
/// breakpoint, a window and a stopwatch.
///
/// Two things are asserted, not one. No two actions overlap, which is the bug; **and** the view
/// left on screen does eventually load, which is the trap the first attempt at this fix fell into
/// — a rebuilt view brings a fresh `@StateObject` with it, so refusing its first appearance
/// outright leaves the model the developer is looking at empty for good.
@MainActor
final class FirstAppearModifierTests: XCTestCase {

    /// A view whose first-appear suspends until the recorder is released.
    ///
    /// `identity` is threaded onto `.id`, so handing the hosting controller a probe with a
    /// different one is what makes SwiftUI discard the old view — and the old `@State` — and build
    /// a fresh one in its place.
    fileprivate struct Probe: View {
        let identity: Int
        let recorder: FirstAppearRecorder

        var body: some View {
            Leaf(recorder: recorder)
                .id(identity)
        }
    }

    /// The view whose state the first appearance loads.
    ///
    /// It owns its model as a `@StateObject`, exactly as every screen in Scyther does, so the
    /// model dies with the view when SwiftUI discards it — which is the whole reason a refused
    /// first appearance is worse than a repeated one. The recorder outlives the rebuilds and
    /// counts them; the model does not, and is what the surviving view is checked for.
    fileprivate struct Leaf: View {
        let recorder: FirstAppearRecorder
        @StateObject private var model = ProbeModel()

        init(recorder: FirstAppearRecorder) {
            self.recorder = recorder
        }

        var body: some View {
            Color.clear
                .onFirstAppear {
                    await recorder.begin()
                    model.isLoaded = true
                    recorder.record(model)
                }
        }
    }

    /// Stands in for the `@StateObject` view model every Scyther screen loads on first appear.
    @MainActor
    fileprivate final class ProbeModel: ObservableObject {
        /// Whether this instance's first appearance ran to completion.
        var isLoaded = false
    }

    private var window: UIWindow!
    private var recorder: FirstAppearRecorder!

    override func setUp() {
        super.setUp()
        recorder = FirstAppearRecorder()
    }

    override func tearDown() {
        recorder?.release()
        window?.isHidden = true
        window = nil
        recorder = nil
        super.tearDown()
    }

    /// Spins the run loop until `condition` holds, so SwiftUI gets a chance to run its `task`s.
    @discardableResult
    private func waitUntil(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// Gives SwiftUI and the concurrency runtime a fixed slice of run loop to do their worst.
    private func settle(_ seconds: TimeInterval = 0.3) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// Hosts a probe, laid out and on screen, so its `task` actually runs.
    private func host(identity: Int) -> UIHostingController<Probe> {
        let controller = UIHostingController(rootView: Probe(identity: identity, recorder: recorder))
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        return controller
    }

    /// The defect: a view re-created while its first-appear is still suspended must not start it
    /// a second time.
    func testARunningFirstAppearIsNotStartedAgainWhenTheViewIsReCreated() {
        let controller = host(identity: 1)

        XCTAssertTrue(waitUntil { self.recorder.started == 1 }, "the first appearance runs the action")

        // The action is still suspended. Replace the view, exactly as a presentation over it does.
        for identity in 2...5 {
            controller.rootView = Probe(identity: identity, recorder: recorder)
            window.layoutIfNeeded()
            settle(0.2)
        }

        XCTAssertEqual(recorder.started, 1,
                       "a first-appear still running must not be re-entered, however often the view is rebuilt")
        XCTAssertEqual(recorder.finished, 0, "and it is genuinely still running, not quietly finished")

        recorder.release()
        _ = waitUntil { self.recorder.finished >= 1 }
    }

    /// The other half, and the reason the queue does not simply refuse a latecomer: SwiftUI threw
    /// the first view away and its `@StateObject` with it, so the model on screen belongs to the
    /// view that arrived second. If that one is refused, the screen never loads at all.
    func testTheViewLeftOnScreenIsLoadedEvenThoughItArrivedSecond() {
        let controller = host(identity: 1)
        XCTAssertTrue(waitUntil { self.recorder.started == 1 })

        controller.rootView = Probe(identity: 2, recorder: recorder)
        window.layoutIfNeeded()
        settle(0.2)

        XCTAssertEqual(recorder.started, 1, "the second appearance waits rather than running alongside")

        recorder.release()

        XCTAssertTrue(waitUntil { self.recorder.finished == 2 },
                      "the queued appearance runs once the first has finished")
        XCTAssertEqual(recorder.loaded.count, 2,
                       "both the discarded view's model and the surviving view's model were loaded")
        guard recorder.loaded.count == 2 else { return }

        XCTAssertTrue(recorder.loaded[1].isLoaded,
                      "the model belonging to the view still on screen is the one that got loaded")
        XCTAssertFalse(recorder.loaded[0] === recorder.loaded[1],
                       "and it is a different model from the discarded view's, which is the point")
    }

    /// The other half of the contract: once the action has finished, a genuinely new view is
    /// allowed to run it again. A guard that never released would have stopped a screen that was
    /// left and returned to from ever loading.
    func testAFinishedFirstAppearRunsAgainForANewView() {
        recorder.release()
        let controller = host(identity: 1)

        XCTAssertTrue(waitUntil { self.recorder.finished == 1 })

        controller.rootView = Probe(identity: 2, recorder: recorder)
        window.layoutIfNeeded()

        XCTAssertTrue(waitUntil { self.recorder.started == 2 },
                      "a new view with no action in flight starts its own first appearance")
    }
}

/// The half of the guard that outlives the view, tested directly.
///
/// The hosted tests above prove the behaviour end to end; these pin the contract the modifier
/// rests on, one clause at a time.
@MainActor
final class FirstAppearGuardTests: XCTestCase {

    private let key = FirstAppearGuard.Key(fileID: "Scyther/Probe.swift", line: 1, column: 1, id: nil)

    func testTheFirstCallerRuns() async {
        let firstAppear = FirstAppearGuard()
        var ran = false
        let didRun = await firstAppear.run(key) { ran = true }
        XCTAssertTrue(didRun)
        XCTAssertTrue(ran)
    }

    func testASecondCallerWaitsForTheFirstRatherThanRunningAlongsideIt() async {
        let firstAppear = FirstAppearGuard()
        let recorder = FirstAppearRecorder()

        let first = Task { await firstAppear.run(self.key) { await recorder.begin() } }
        while !firstAppear.isRunning(key) { await Task.yield() }

        var secondRan = false
        let second = Task { await firstAppear.run(self.key) { secondRan = true } }

        // Give the second every chance to run alongside the first.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(secondRan, "a suspended action must not be re-entered")

        recorder.release()
        _ = await first.value
        _ = await second.value
        XCTAssertTrue(secondRan, "but it is queued, not dropped — it runs once the first is done")
    }

    /// The bound that stops a first-appear which never returns bricking its screen for the life of
    /// the process. Swift cancellation is cooperative and `NetworkHelper.ipAddress` ignores it, so
    /// there is nothing else standing between a hung action and a screen that can never load.
    func testAWaiterGoesAheadOnceTheIncumbentHasOverrunItsDeadline() async {
        let firstAppear = FirstAppearGuard()
        firstAppear.maximumWait = 0.2
        let recorder = FirstAppearRecorder()

        let first = Task { await firstAppear.run(self.key) { await recorder.begin() } }
        while !firstAppear.isRunning(key) { await Task.yield() }

        /// Bounded rather than simply awaited: without the deadline the waiter never proceeds at
        /// all, and a test that hangs for the whole XCTest timeout says far less than one that
        /// fails on the assertion below.
        var secondRan = false
        let second = Task { await firstAppear.run(self.key) { secondRan = true } }
        let started = Date()
        while !secondRan, Date().timeIntervalSince(started) < 2 {
            await Task.yield()
        }

        XCTAssertTrue(secondRan, "a hung first appearance costs a wait, not the screen")
        XCTAssertEqual(recorder.finished, 0, "and the hung one really was still running")

        second.cancel()
        _ = await second.value
        recorder.release()
        _ = await first.value
    }

    /// A waiter whose view has gone away drops out, so the queue prunes itself to the screens
    /// still on the glass rather than running an action against a model nobody is rendering.
    func testACancelledWaiterStopsWaitingAndDoesNotRun() async {
        let firstAppear = FirstAppearGuard()
        let recorder = FirstAppearRecorder()

        let first = Task { await firstAppear.run(self.key) { await recorder.begin() } }
        while !firstAppear.isRunning(key) { await Task.yield() }

        var secondRan = false
        let second = Task { await firstAppear.run(self.key) { secondRan = true } }
        for _ in 0..<20 { await Task.yield() }
        second.cancel()

        let didRunSecond = await second.value
        XCTAssertFalse(didRunSecond)
        XCTAssertFalse(secondRan)

        recorder.release()
        _ = await first.value
    }

    func testTheKeyIsReleasedOnceTheActionEnds() async {
        let firstAppear = FirstAppearGuard()
        _ = await firstAppear.run(key) { }
        XCTAssertFalse(firstAppear.isRunning(key))

        var ranAgain = false
        let didRun = await firstAppear.run(key) { ranAgain = true }
        XCTAssertTrue(didRun)
        XCTAssertTrue(ranAgain)
    }

    /// Different call sites are independent: one screen's slow load must never delay another's.
    func testDifferentCallSitesDoNotBlockEachOther() async {
        let firstAppear = FirstAppearGuard()
        let recorder = FirstAppearRecorder()
        let other = FirstAppearGuard.Key(fileID: "Scyther/Probe.swift", line: 2, column: 1, id: nil)

        let first = Task { await firstAppear.run(self.key) { await recorder.begin() } }
        while !firstAppear.isRunning(key) { await Task.yield() }

        let didRunOther = await firstAppear.run(other) { }
        XCTAssertTrue(didRunOther, "a different call site has its own entry")

        recorder.release()
        _ = await first.value
    }

    /// The `id:` discriminator, which is what `FileBrowserView` and `LogDetailsView` pass because
    /// they push themselves: a parent and its child share one call site and must not queue behind
    /// each other.
    func testTheDiscriminatorSeparatesTwoViewsSharingOneCallSite() async {
        let firstAppear = FirstAppearGuard()
        let recorder = FirstAppearRecorder()
        let child = FirstAppearGuard.Key(fileID: key.fileID, line: key.line, column: key.column, id: "child")

        let first = Task { await firstAppear.run(self.key) { await recorder.begin() } }
        while !firstAppear.isRunning(key) { await Task.yield() }

        let didRunChild = await firstAppear.run(child) { }
        XCTAssertTrue(didRunChild, "the pushed copy loads while its parent is still loading")

        recorder.release()
        _ = await first.value
    }
}
