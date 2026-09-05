//
//  HeldRequestViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class HeldRequestEditorViewModelTests: XCTestCase {

    /// Records what a continuation was handed.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [BreakpointResolution] = []

        var resume: @Sendable (BreakpointResolution) -> Void {
            { [self] resolution in lock.withLock { storage.append(resolution) } }
        }

        var resolutions: [BreakpointResolution] { lock.withLock { storage } }
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

    @discardableResult
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// Holds a request and hands back the pause the UI would be showing.
    private func heldRequest(_ recorder: Recorder) throws -> PendingBreakpoint {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/users")!)
        request.httpMethod = "POST"
        request.setValue("Bearer original", forHTTPHeaderField: "Authorization")
        coordinator.pause(BreakpointDraft(request: request),
                          name: "cart",
                          stage: .request,
                          timeout: 60,
                          resume: recorder.resume)
        waitUntil { !coordinator.pending.isEmpty }
        return try XCTUnwrap(coordinator.pending.first)
    }

    /// The picker offers the standard methods, and the captured one is always among them — a
    /// picker that could not represent an unusual method would quietly rewrite the request.
    func testThePickerAlwaysOffersTheMethodTheRequestActuallyCarried() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        XCTAssertTrue(viewModel.selectableMethods.contains("GET"))
        XCTAssertTrue(viewModel.selectableMethods.contains("DELETE"))
        XCTAssertTrue(viewModel.selectableMethods.contains(viewModel.method),
                      "the held request's own method has to be selectable")

        viewModel.method = "PROPFIND"
        XCTAssertEqual(viewModel.selectableMethods.first, "PROPFIND",
                       "an unusual method is offered first rather than dropped")
        XCTAssertEqual(viewModel.selectableMethods.count,
                       NetworkRuleEditorViewModel.availableMethods.count + 1)
    }

    /// `URLSession` hands a body to a `URLProtocol` as a stream, not as `httpBody`, so reading
    /// the property directly reported every POST as empty and left the body uneditable for the
    /// requests most worth holding.
    func testAStreamedRequestBodyIsCaptured() throws {
        let recorder = Recorder()
        var request = URLRequest(url: URL(string: "https://api.example.com/graphql")!)
        request.httpMethod = "POST"
        request.httpBodyStream = InputStream(data: Data(#"{"query":"{ me }"}"#.utf8))

        coordinator.pause(BreakpointDraft(request: request),
                          name: "graphql",
                          stage: .request,
                          timeout: 60,
                          resume: recorder.resume)
        waitUntil { !coordinator.pending.isEmpty }
        let pending = try XCTUnwrap(coordinator.pending.first)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        XCTAssertEqual(viewModel.bodyText, #"{"query":"{ me }"}"#,
                       "a streamed body has to reach the editor, or it cannot be edited")
        coordinator.resolve(id: pending.id, with: .continue(pending.draft))
    }

    func testContinuingCarriesTheEdits() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        viewModel.method = "PUT"
        viewModel.addHeader()
        viewModel.draft.headers[viewModel.draft.headers.count - 1] = .init(name: "X-Held", value: "1")
        viewModel.continueWithEdits()

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .continue(let draft) = try XCTUnwrap(recorder.resolutions.first) else {
            return XCTFail("expected continue")
        }
        XCTAssertEqual(draft.method, "PUT")
        XCTAssertEqual(draft.headers.first { $0.name == "X-Held" }?.value, "1")
    }

    /// "Without changes" has to stay true however much has been typed into the form, which is why
    /// the editable copy lives on the view model rather than on the pause.
    func testContinuingWithoutChangesIgnoresWhatWasTyped() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        viewModel.method = "DELETE"
        viewModel.continueUnchanged()

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .continue(let draft) = try XCTUnwrap(recorder.resolutions.first) else {
            return XCTFail("expected continue")
        }
        XCTAssertEqual(draft.method, "POST", "the exchange as it was held")
        XCTAssertEqual(draft, pending.draft)
    }

    func testAbortingCarriesTheChosenCode() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        viewModel.abort(with: .notConnectedToInternet)

        XCTAssertTrue(waitUntil { recorder.resolutions.count == 1 })
        guard case .abort(let code) = try XCTUnwrap(recorder.resolutions.first) else {
            return XCTFail("expected abort")
        }
        XCTAssertEqual(code, .notConnectedToInternet)
    }

    func testEditingIsReportedAndTypingItBackIsNot() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)
        XCTAssertFalse(viewModel.isEdited)

        viewModel.method = "PUT"
        XCTAssertTrue(viewModel.isEdited)

        viewModel.method = "POST"
        XCTAssertFalse(viewModel.isEdited, "putting a value back is not an edit")
    }

    func testAnInvalidURLIsReportedRatherThanRefused() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        viewModel.url = "not a url at all"
        XCTAssertFalse(viewModel.hasValidURL)
    }

    func testTheBodyReadsAndWritesAsText() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        viewModel.bodyText = "{\"a\":1}"
        XCTAssertEqual(viewModel.draft.body, Data("{\"a\":1}".utf8))
        XCTAssertTrue(viewModel.bodySummary.contains("7"))
    }

    func testTheCountdownCountsDownAndStopsAtZero() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        let viewModel = HeldRequestEditorViewModel(pending: pending, coordinator: coordinator)

        XCTAssertEqual(viewModel.remainingText(at: pending.deadline.addingTimeInterval(-30)),
                       NetworkBreakpoint.secondsText(30))
        XCTAssertEqual(viewModel.remainingText(at: pending.deadline.addingTimeInterval(60)),
                       NetworkBreakpoint.secondsText(0),
                       "an overdue pause never counts below zero")
    }

    func testTheTitleNamesTheSideBeingHeld() throws {
        let recorder = Recorder()
        let pending = try heldRequest(recorder)
        XCTAssertEqual(HeldRequestEditorViewModel(pending: pending, coordinator: coordinator).title,
                       localized("Held Request"))

        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://api.example.com/v1/users")!,
                                                     statusCode: 500,
                                                     httpVersion: nil,
                                                     headerFields: nil))
        coordinator.pause(BreakpointDraft(response: response, body: Data()),
                          name: "cart",
                          stage: .response,
                          timeout: 60) { _ in }
        waitUntil { coordinator.pending.count == 2 }
        let held = try XCTUnwrap(coordinator.pending.first { $0.stage == .response })
        let viewModel = HeldRequestEditorViewModel(pending: held, coordinator: coordinator)
        XCTAssertEqual(viewModel.title, localized("Held Response"))
        XCTAssertFalse(viewModel.isRequest)
        XCTAssertEqual(viewModel.statusCode, 500)
    }

    func testEveryAbortCodeIsNamed() {
        for code in HeldRequestEditorViewModel.abortCodes {
            XCTAssertNotEqual(code.abortTitle, "\(code.rawValue)", "\(code) should have a label")
        }
    }
}

@MainActor
final class HeldRequestsViewModelTests: XCTestCase {

    private func pending(_ name: String) -> PendingBreakpoint {
        PendingBreakpoint(
            id: UUID(),
            breakpointName: name,
            stage: .request,
            draft: BreakpointDraft(request: URLRequest(url: URL(string: "https://api.example.com/\(name)")!)),
            deadline: Date().addingTimeInterval(60)
        )
    }

    /// One held exchange opens straight into its editor: a list of one row in front of a paused
    /// app is a tap that teaches nothing.
    func testASinglePauseOpensItsEditor() {
        let viewModel = HeldRequestsViewModel()
        let only = pending("cart")

        viewModel.pendingChanged([only])

        XCTAssertEqual(viewModel.path, [only.id])
    }

    func testSeveralPausesShowTheListInstead() {
        let viewModel = HeldRequestsViewModel()
        viewModel.pendingChanged([pending("cart"), pending("checkout")])
        XCTAssertTrue(viewModel.path.isEmpty)
    }

    /// A pause resolved by its timeout, or by the app cancelling the request, takes its editor
    /// with it rather than leaving a form editing something that has gone.
    func testAResolvedPauseIsPoppedOffThePath() {
        let viewModel = HeldRequestsViewModel()
        let first = pending("cart")
        let second = pending("checkout")
        viewModel.pendingChanged([first, second])
        viewModel.path = [second.id]

        viewModel.pendingChanged([first])

        XCTAssertEqual(viewModel.path, [first.id],
                       "the one left is opened, because it is now the only one")
    }

    func testAnEmptyListLeavesNothingPushed() {
        let viewModel = HeldRequestsViewModel()
        let only = pending("cart")
        viewModel.pendingChanged([only])

        viewModel.pendingChanged([])

        XCTAssertTrue(viewModel.path.isEmpty)
    }
}
