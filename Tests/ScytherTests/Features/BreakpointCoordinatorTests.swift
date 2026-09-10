//
//  BreakpointCoordinatorTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class BreakpointCoordinatorTests: XCTestCase {

    /// Records what a continuation was handed, and on which thread.
    ///
    /// The continuation runs on the coordinator's own queue, so everything it writes is read from
    /// another thread and has to be synchronised.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [BreakpointResolution] = []
        private var mainThreadCalls = 0

        /// Called by the coordinator when a pause resolves.
        var resume: @Sendable (BreakpointResolution) -> Void {
            { [self] resolution in
                lock.withLock {
                    storage.append(resolution)
                    if Thread.isMainThread { mainThreadCalls += 1 }
                }
            }
        }

        /// Every resolution delivered so far, oldest first.
        var resolutions: [BreakpointResolution] { lock.withLock { storage } }

        /// How many resolutions were delivered on the main thread.
        var mainThreadDeliveries: Int { lock.withLock { mainThreadCalls } }
    }

    private var coordinator: BreakpointCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = BreakpointCoordinator()
    }

    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }

    private func draft() -> BreakpointDraft {
        BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/v1/users")!))
    }

    /// Spins the run loop until `condition` holds, rather than sleeping a fixed amount and hoping.
    ///
    /// - Returns: Whether it held before `timeout` elapsed.
    @discardableResult
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// The identifier of the pause the UI can see, once the coordinator has published it.
    @MainActor
    private func pendingID() -> UUID? {
        waitUntil { !coordinator.pending.isEmpty }
        return coordinator.pending.first?.id
    }

    // MARK: - Not blocking

    /// The whole point of the primitive. `pause` is called from a thread the URL loading system
    /// owns, and an earlier draft of this design blocked that thread on a semaphore for up to five
    /// minutes.
    @MainActor
    func testPauseReturnsImmediatelyAndBlocksNothing() {
        let recorder = Recorder()

        let start = Date()
        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        let returned = Date().timeIntervalSince(start)

        XCTAssertLessThan(returned, 0.2, "pause must never hold the thread it was called on")
        XCTAssertTrue(recorder.resolutions.isEmpty, "and must not have resolved anything yet")
    }

    /// Called on the main thread and returning at once, the pause is still live: the UI sees it
    /// and can resolve it. A guard that skipped a main-thread pause would make this impossible.
    @MainActor
    func testAPauseTakenOnTheMainThreadIsStillHeld() throws {
        let recorder = Recorder()
        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)

        let id = try XCTUnwrap(pendingID())
        coordinator.resolve(id: id, with: .timedOut)

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
    }

    /// The continuation belongs to the coordinator's queue, not to the main actor: it starts data
    /// tasks and hands bytes to the client, neither of which should run on the UI thread.
    @MainActor
    func testTheContinuationRunsOffTheMainThread() throws {
        let recorder = Recorder()
        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        let id = try XCTUnwrap(pendingID())

        coordinator.resolve(id: id, with: .timedOut)

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        XCTAssertEqual(recorder.mainThreadDeliveries, 0)
    }

    // MARK: - Resolving

    @MainActor
    func testResolvingWithContinueDeliversTheEditedDraft() throws {
        let recorder = Recorder()
        var edited = draft()
        edited.method = "DELETE"

        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        let id = try XCTUnwrap(pendingID())
        coordinator.resolve(id: id, with: .continue(edited))

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .continue(let returned) = try XCTUnwrap(recorder.resolutions.first) else {
            return XCTFail("expected continue")
        }
        XCTAssertEqual(returned.method, "DELETE")
    }

    @MainActor
    func testResolvingWithAbortDeliversTheCode() throws {
        let recorder = Recorder()
        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        let id = try XCTUnwrap(pendingID())

        coordinator.resolve(id: id, with: .abort(.cancelled))

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .abort(let code) = try XCTUnwrap(recorder.resolutions.first) else {
            return XCTFail("expected abort")
        }
        XCTAssertEqual(code, .cancelled)
    }

    @MainActor
    func testAResolvedPauseLeavesThePendingList() throws {
        let recorder = Recorder()
        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        let id = try XCTUnwrap(pendingID())

        coordinator.resolve(id: id, with: .timedOut)

        XCTAssertTrue(coordinator.pending.isEmpty, "the row goes the moment the developer decides")
    }

    /// A double tap on Continue — or a resolution racing the timeout — delivers once.
    @MainActor
    func testResolvingTwiceDeliversOneResolution() throws {
        let recorder = Recorder()
        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        let id = try XCTUnwrap(pendingID())

        coordinator.resolve(id: id, with: .timedOut)
        coordinator.resolve(id: id, with: .abort(.cancelled))

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        XCTAssertFalse(waitUntil(0.3) { recorder.resolutions.count > 1 })
    }

    @MainActor
    func testResolvingSomethingUnknownIsIgnored() {
        coordinator.resolve(id: UUID(), with: .timedOut)
        XCTAssertTrue(coordinator.pending.isEmpty)
    }

    // MARK: - Timing out

    @MainActor
    func testAnUnresolvedPauseTimesOut() {
        let recorder = Recorder()
        let start = Date()
        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 0.4, resume: recorder.resume)

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .timedOut = recorder.resolutions[0] else {
            return XCTFail("expected timedOut, got \(recorder.resolutions[0])")
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.4)
        XCTAssertTrue(waitUntil { coordinator.pending.isEmpty }, "the row goes with it")
    }

    // MARK: - Cancelling

    /// `stopLoading()` calls this. A client that has gone away must be handed nothing at all —
    /// not a continue, not a timeout — because delivering to a cancelled client is something the
    /// `URLProtocol` contract forbids.
    ///
    /// The timeout is long enough that none can fire inside this test, which is deliberate: this
    /// asserts that cancelling delivers nothing, and racing a short deadline against the
    /// cancellation asserted instead that the machine got to `cancel(id:)` inside 0.3 seconds —
    /// which a loaded runner does not promise, and a pause nobody cancelled in time is *supposed*
    /// to time out. What happens when a timeout does arrive after a cancellation is
    /// ``testResolvingAfterCancellingDeliversNothing``, which delivers one by hand rather than
    /// waiting on the clock for it.
    @MainActor
    func testACancelledPauseNeverResumes() throws {
        let recorder = Recorder()
        let id = coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        _ = pendingID()

        coordinator.cancel(id: id)

        XCTAssertFalse(waitUntil(1) { !recorder.resolutions.isEmpty },
                       "a cancelled pause delivers nothing")
        XCTAssertTrue(coordinator.pending.isEmpty, "and it leaves no row behind either")
    }

    /// Every late decision, the timeout included: ``pause(_:name:stage:timeout:resume:)``'s work
    /// item and `resolve(id:with:)` reach the same delivery on the same queue, so a `.timedOut`
    /// handed over after a cancellation is the armed timeout arriving late — at a moment this
    /// test chooses, rather than one it has to wait out.
    @MainActor
    func testResolvingAfterCancellingDeliversNothing() throws {
        let recorder = Recorder()
        let id = coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60, resume: recorder.resume)
        _ = pendingID()

        coordinator.cancel(id: id)
        coordinator.resolve(id: id, with: .continue(draft()))
        coordinator.resolve(id: id, with: .timedOut)

        XCTAssertFalse(waitUntil(0.5) { !recorder.resolutions.isEmpty })
    }

    // MARK: - Concurrency

    @MainActor
    func testConcurrentPausesResolveIndependently() throws {
        let first = Recorder()
        let second = Recorder()

        coordinator.pause(draft(), name: "a", stage: .request, timeout: 60, resume: first.resume)
        coordinator.pause(draft(), name: "b", stage: .response, timeout: 60, resume: second.resume)
        XCTAssertTrue(waitUntil { coordinator.pending.count == 2 })

        let bID = try XCTUnwrap(coordinator.pending.first { $0.breakpointName == "b" }?.id)
        coordinator.resolve(id: bID, with: .abort(.timedOut))

        XCTAssertTrue(waitUntil { second.resolutions.count == 1 })
        XCTAssertTrue(first.resolutions.isEmpty, "resolving one must not resolve the other")
        XCTAssertEqual(coordinator.pending.map(\.breakpointName), ["a"])
    }

    /// Pauses taken from several threads at once all arrive, which is what a burst of matching
    /// requests looks like.
    @MainActor
    func testPausesTakenFromManyThreadsAllArrive() {
        let recorders = (0..<8).map { _ in Recorder() }
        let group = DispatchGroup()
        for (index, recorder) in recorders.enumerated() {
            group.enter()
            DispatchQueue.global().async { [coordinator] in
                coordinator?.pause(BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/\(index)")!)),
                                   name: "burst \(index)",
                                   stage: .request,
                                   timeout: 60,
                                   resume: recorder.resume)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(waitUntil { coordinator.pending.count == 8 })

        for item in coordinator.pending {
            coordinator.resolve(id: item.id, with: .timedOut)
        }
        XCTAssertTrue(waitUntil { recorders.allSatisfy { $0.resolutions.count == 1 } })
    }

    // MARK: - The pending item

    @MainActor
    func testAPendingItemCarriesItsNameStageAndDeadline() throws {
        let before = Date()
        coordinator.pause(draft(), name: "cart", stage: .response, timeout: 30) { _ in }

        _ = pendingID()
        let item = try XCTUnwrap(coordinator.pending.first)
        XCTAssertEqual(item.breakpointName, "cart")
        XCTAssertEqual(item.stage, .response)
        XCTAssertEqual(item.draft.url, "https://api.example.com/v1/users")
        XCTAssertGreaterThanOrEqual(item.deadline, before.addingTimeInterval(30))
    }

    /// The presenter subscribes to this to put the editor on screen and take it away again.
    @MainActor
    func testTheChangeHandlerReportsEveryPendingChange() throws {
        nonisolated(unsafe) var counts: [Int] = []
        coordinator.onPendingChanged = { counts.append($0.count) }

        coordinator.pause(draft(), name: "cart", stage: .request, timeout: 60) { _ in }
        XCTAssertTrue(waitUntil { counts == [1] })

        let id = try XCTUnwrap(coordinator.pending.first?.id)
        coordinator.resolve(id: id, with: .timedOut)
        XCTAssertTrue(waitUntil { counts == [1, 0] })
    }

    // MARK: - Timeouts

    /// The timeout used to be scheduled and then forgotten, so a pause that ended early left a
    /// block holding the coordinator on its queue for the whole of a timeout that can be five
    /// minutes long — once per hold, and the coordinator holds every other live pause's
    /// continuation.
    ///
    /// A timeout no shorter than the production ceiling, so a coordinator that survives it is
    /// unambiguously being kept alive by the block rather than by the wait being short.
    @MainActor
    func testACancelledPauseDoesNotLeaveItsTimeoutHoldingTheCoordinator() {
        weak var leaked: BreakpointCoordinator?

        autoreleasepool {
            let live = BreakpointCoordinator()
            leaked = live
            let id = live.pause(draft(), name: "cart", stage: .request, timeout: 300) { _ in }
            XCTAssertTrue(waitUntil { !live.pending.isEmpty })
            live.cancel(id: id)
            /// The cancellation is applied on the coordinator's own queue, so give it a turn to
            /// land before the last strong reference goes.
            XCTAssertTrue(waitUntil { live.pending.isEmpty })
        }

        XCTAssertTrue(waitUntil { leaked == nil },
                      "a cancelled pause must not keep the coordinator alive for its timeout")
    }

    /// The same for the ordinary ending: the developer decided, so the timeout has nothing left to
    /// do.
    @MainActor
    func testAResolvedPauseDoesNotLeaveItsTimeoutHoldingTheCoordinator() throws {
        weak var leaked: BreakpointCoordinator?
        let recorder = Recorder()

        try autoreleasepool {
            let live = BreakpointCoordinator()
            leaked = live
            live.pause(draft(), name: "cart", stage: .request, timeout: 300, resume: recorder.resume)
            XCTAssertTrue(waitUntil { !live.pending.isEmpty })
            live.resolve(id: try XCTUnwrap(live.pending.first?.id), with: .timedOut)
            XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        }

        XCTAssertTrue(waitUntil { leaked == nil },
                      "a resolved pause must not keep the coordinator alive for its timeout")
    }
}
