//
//  ReplayEditorViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class ReplayEditorViewModelTests: XCTestCase {

    /// Collects the requests a view model would have sent, so no test touches the network.
    private final class Outbox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URLRequest] = []

        var requests: [URLRequest] { lock.withLock { storage } }

        func record(_ request: URLRequest) {
            lock.withLock { storage.append(request) }
        }
    }

    private func capture(method: String = "GET",
                         url: String = "https://api.example.com/v1/users",
                         headers: [String: String] = [:]) -> HTTPRequest {
        let mutable = NSMutableURLRequest(url: URL(string: url)!)
        mutable.httpMethod = method
        headers.forEach { mutable.setValue($0.value, forHTTPHeaderField: $0.key) }
        let model = HTTPRequest()
        model.saveRequest(mutable as URLRequest)
        return model
    }

    private func viewModel(_ capture: HTTPRequest, outbox: Outbox = Outbox()) -> ReplayEditorViewModel {
        ReplayEditorViewModel(capturing: capture, dispatch: { outbox.record($0) })
    }

    // MARK: - Validation

    func testSendIsDisabledForAnInvalidURL() {
        let viewModel = viewModel(capture())
        XCTAssertTrue(viewModel.canSend)
        viewModel.draft.url = "not a url"
        XCTAssertFalse(viewModel.canSend)
        XCTAssertFalse(viewModel.hasValidURL)
    }

    func testSendIsDisabledForAnEmptyMethod() {
        let viewModel = viewModel(capture())
        viewModel.draft.method = "  "
        XCTAssertFalse(viewModel.canSend)
    }

    func testNonIdempotentMethodsRequireConfirmation() {
        for method in ["POST", "PATCH", "DELETE", "post"] {
            let viewModel = viewModel(capture(method: method))
            XCTAssertTrue(viewModel.requiresConfirmation, "\(method) can change server state twice")
        }
        for method in ["GET", "HEAD", "OPTIONS"] {
            let viewModel = viewModel(capture(method: method))
            XCTAssertFalse(viewModel.requiresConfirmation)
        }
    }

    func testAnUnknownMethodRequiresConfirmation() {
        let viewModel = viewModel(capture(method: "PURGE"))
        XCTAssertTrue(viewModel.requiresConfirmation, "a verb we do not recognise is assumed to change state")
    }

    func testConfirmationFollowsTheEditedMethodNotTheCapturedOne() {
        let viewModel = viewModel(capture(method: "GET"))
        XCTAssertFalse(viewModel.requiresConfirmation)
        viewModel.methodSelection = "DELETE"
        XCTAssertTrue(viewModel.requiresConfirmation)
    }

    func testNormalisedMethodIsUppercasedAndTrimmed() {
        let viewModel = viewModel(capture())
        viewModel.draft.method = " patch "
        XCTAssertEqual(viewModel.normalisedMethod, "PATCH")
    }

    // MARK: - The method picker

    func testTheMethodPickerStartsOnACapturedListedVerb() {
        let viewModel = viewModel(capture(method: "delete"))
        XCTAssertEqual(viewModel.methodSelection, "DELETE", "a listed verb is matched however it was cased")
        XCTAssertEqual(viewModel.customMethod, "")
    }

    func testTheMethodPickerStartsOnOtherForAnUnlistedVerb() {
        let viewModel = viewModel(capture(method: "PURGE"))
        XCTAssertEqual(viewModel.methodSelection, ReplayEditorViewModel.otherMethodTag)
        XCTAssertEqual(viewModel.customMethod, "PURGE")
        XCTAssertEqual(viewModel.draft.method, "PURGE")
    }

    func testChoosingAVerbUpdatesTheDraft() {
        let viewModel = viewModel(capture(method: "GET"))
        viewModel.methodSelection = "PUT"
        XCTAssertEqual(viewModel.draft.method, "PUT")
    }

    func testChoosingOtherAdoptsTheCustomMethod() {
        let viewModel = viewModel(capture(method: "GET"))
        viewModel.methodSelection = ReplayEditorViewModel.otherMethodTag
        viewModel.customMethod = "PURGE"
        XCTAssertEqual(viewModel.draft.method, "PURGE")
    }

    func testSwitchingBackToAVerbKeepsWhatWasTypedIntoOther() {
        let viewModel = viewModel(capture(method: "GET"))
        viewModel.methodSelection = ReplayEditorViewModel.otherMethodTag
        viewModel.customMethod = "PURGE"
        viewModel.methodSelection = "GET"
        XCTAssertEqual(viewModel.draft.method, "GET")
        XCTAssertEqual(viewModel.customMethod, "PURGE", "the typed verb is remembered")
        viewModel.methodSelection = ReplayEditorViewModel.otherMethodTag
        XCTAssertEqual(viewModel.draft.method, "PURGE")
    }

    func testTypingIntoTheCustomMethodWhileAVerbIsSelectedDoesNotChangeTheDraft() {
        let viewModel = viewModel(capture(method: "GET"))
        viewModel.customMethod = "PURGE"
        XCTAssertEqual(viewModel.draft.method, "GET")
    }

    // MARK: - Headers

    func testEditingAHeaderMarksTheDraftModified() {
        let viewModel = viewModel(capture())
        XCTAssertFalse(viewModel.isModified)
        viewModel.draft.headers.append(.init(name: "X-Debug", value: "1"))
        XCTAssertTrue(viewModel.isModified)
    }

    func testRemovingAHeaderMarksTheDraftModified() {
        let viewModel = viewModel(capture())
        viewModel.draft.headers.append(.init(name: "X-Debug", value: "1"))
        let count = viewModel.draft.headers.count
        viewModel.draft.headers.removeLast()
        XCTAssertEqual(viewModel.draft.headers.count, count - 1)
        XCTAssertFalse(viewModel.isModified, "removing the added header returns the draft to its original state")
    }

    func testAddingAndRemovingHeaderRows() {
        let viewModel = viewModel(capture(headers: ["Authorization": "Bearer abc"]))
        XCTAssertEqual(viewModel.draft.headers.count, 1)
        viewModel.addHeader()
        XCTAssertEqual(viewModel.draft.headers.count, 2)
        XCTAssertEqual(viewModel.draft.headers.last?.name, "")
        viewModel.removeHeaders(at: IndexSet(integer: 0))
        XCTAssertEqual(viewModel.draft.headers.map(\.name), [""])
    }

    // MARK: - Sending

    func testSendStampsProvenanceAndDispatchesOnce() throws {
        let capture = capture(method: "POST")
        let outbox = Outbox()
        let viewModel = viewModel(capture, outbox: outbox)
        viewModel.draft.headers.append(.init(name: "X-Debug", value: "1"))

        let sent = try XCTUnwrap(viewModel.send())

        XCTAssertEqual(outbox.requests.count, 1, "a replay goes out exactly once")
        XCTAssertEqual(sent.url?.absoluteString, "https://api.example.com/v1/users")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Debug"), "1")
        XCTAssertEqual(URLProtocol.property(forKey: replayOfRequestKey, in: sent) as? String,
                       capture.getRandomHash() as String)
    }

    func testSendDoesNothingWhenTheDraftCannotBeBuilt() {
        let outbox = Outbox()
        let viewModel = viewModel(capture(), outbox: outbox)
        viewModel.draft.url = "not a url"
        XCTAssertNil(viewModel.send())
        XCTAssertTrue(outbox.requests.isEmpty)
    }

    func testTheReplayIsStampedWithTheOriginalNotItself() throws {
        let first = capture()
        let second = capture()
        let sent = try XCTUnwrap(viewModel(first).send())
        XCTAssertEqual(URLProtocol.property(forKey: replayOfRequestKey, in: sent) as? String,
                       first.getRandomHash() as String)
        XCTAssertNotEqual(URLProtocol.property(forKey: replayOfRequestKey, in: sent) as? String,
                          second.getRandomHash() as String)
    }
}
