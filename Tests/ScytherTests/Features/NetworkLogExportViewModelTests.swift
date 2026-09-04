//
//  NetworkLogExportViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class NetworkLogExportViewModelTests: XCTestCase {

    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).zip")
        try Data("PK".utf8).write(to: url)
        return url
    }

    func testStartsPreparingThenBecomesReadyWithArchive() async throws {
        let file = try makeTempFile()
        let requests = [HTTPRequest(), HTTPRequest()]
        let viewModel = NetworkLogExportViewModel(requests: requests, minimumRebuildDuration: .zero) { _, _ in file }

        XCTAssertEqual(viewModel.state, .preparing)
        XCTAssertEqual(viewModel.requestCount, 2)

        await viewModel.onFirstAppear()

        XCTAssertEqual(viewModel.state, .ready(file))
        XCTAssertEqual(viewModel.archiveURL, file)
        XCTAssertEqual(viewModel.archiveFilename, file.lastPathComponent)
    }

    func testFailureIsReported() async {
        struct Boom: Error {}
        let viewModel = NetworkLogExportViewModel(requests: [HTTPRequest()], minimumRebuildDuration: .zero) { _, _ in throw Boom() }
        await viewModel.onFirstAppear()
        guard case .failed = viewModel.state else {
            return XCTFail("expected failed state, got \(viewModel.state)")
        }
        XCTAssertNil(viewModel.archiveURL)
    }

    func testCleanupRemovesArchive() async throws {
        let file = try makeTempFile()
        let viewModel = NetworkLogExportViewModel(requests: [HTTPRequest()], minimumRebuildDuration: .zero) { _, _ in file }
        await viewModel.onFirstAppear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        viewModel.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRedactionDefaultsOnAndTogglingRebuildsWithFlag() async throws {
        final class Box: @unchecked Sendable { var flags: [Bool] = [] }
        let first = try makeTempFile()
        let second = try makeTempFile()
        let box = Box()
        let viewModel = NetworkLogExportViewModel(requests: [HTTPRequest()], minimumRebuildDuration: .zero) { _, redact in
            box.flags.append(redact)
            return redact ? first : second
        }
        XCTAssertTrue(viewModel.redactSensitiveValues)
        await viewModel.onFirstAppear()
        XCTAssertEqual(viewModel.archiveURL, first)

        let task = viewModel.setRedaction(false)
        XCTAssertFalse(viewModel.redactSensitiveValues, "flag flips synchronously so the toggle never bounces")
        XCTAssertTrue(viewModel.isRebuilding)
        await task?.value
        XCTAssertEqual(box.flags, [true, false])
        XCTAssertEqual(viewModel.archiveURL, second)
        XCTAssertFalse(viewModel.isRebuilding)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "previous archive should be removed")
    }

    func testRebuildKeepsPreviousArchiveVisibleUntilReplaced() async throws {
        final class Gate: @unchecked Sendable {
            let semaphore = DispatchSemaphore(value: 0)
            var calls = 0
        }
        let first = try makeTempFile()
        let second = try makeTempFile()
        let gate = Gate()
        let viewModel = NetworkLogExportViewModel(requests: [HTTPRequest()], minimumRebuildDuration: .zero) { _, redact in
            gate.calls += 1
            if !redact { gate.semaphore.wait() }
            return redact ? first : second
        }
        await viewModel.onFirstAppear()

        let rebuild = viewModel.setRedaction(false)
        while gate.calls < 2 { await Task.yield() }

        XCTAssertTrue(viewModel.isRebuilding)
        XCTAssertEqual(viewModel.state, .ready(first), "previous archive stays in the ready state while rebuilding")
        XCTAssertFalse(viewModel.redactSensitiveValues, "toggle reflects the new value immediately")

        gate.semaphore.signal()
        await rebuild?.value
        XCTAssertFalse(viewModel.isRebuilding)
        XCTAssertEqual(viewModel.state, .ready(second))
    }

    func testRebuildHonoursMinimumDuration() async throws {
        let file = try makeTempFile()
        let viewModel = NetworkLogExportViewModel(requests: [HTTPRequest()], minimumRebuildDuration: .milliseconds(300)) { _, _ in file }
        await viewModel.onFirstAppear()

        let start = ContinuousClock.now
        await viewModel.setRedaction(false)?.value
        let elapsed = ContinuousClock.now - start
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(300))
        XCTAssertFalse(viewModel.isRebuilding)
    }

    func testDefaultMinimumRebuildDurationIs750Milliseconds() {
        XCTAssertEqual(NetworkLogExportViewModel.defaultMinimumRebuildDuration, .milliseconds(750))
    }

    func testSettingSameRedactionValueIsNoOp() async throws {
        let file = try makeTempFile()
        let viewModel = NetworkLogExportViewModel(requests: [HTTPRequest()], minimumRebuildDuration: .zero) { _, _ in file }
        await viewModel.onFirstAppear()
        XCTAssertNil(viewModel.setRedaction(true))
        XCTAssertFalse(viewModel.isRebuilding)
    }

    func testExporterReceivesTheGivenRequests() async throws {
        final class Box: @unchecked Sendable { var received: [HTTPRequest] = [] }
        let file = try makeTempFile()
        let a = HTTPRequest(), b = HTTPRequest()
        let box = Box()
        let viewModel = NetworkLogExportViewModel(requests: [a, b], minimumRebuildDuration: .zero) { requests, _ in box.received = requests; return file }
        await viewModel.onFirstAppear()
        XCTAssertTrue(box.received[0] === a && box.received[1] === b)
    }
}
