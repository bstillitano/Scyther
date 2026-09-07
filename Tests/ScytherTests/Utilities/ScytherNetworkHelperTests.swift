//
//  ScytherNetworkHelper.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

@testable import Scyther
import XCTest

/// Answers the ipify lookup without a network, and counts how many times it was asked.
///
/// Registered ahead of everything else for the duration of a test, so it is consulted first — and
/// unregistered again, so it cannot answer another suite's traffic.
private final class CountingIPAddressProtocol: URLProtocol, @unchecked Sendable {
    /// Guards ``requestCount``, which is written from the URL loading system's threads and read
    /// from the test's.
    private static let lock = NSLock()

    /// How many lookups have reached the network layer.
    ///
    /// - Note: `nonisolated(unsafe)` because every access goes through ``lock``.
    nonisolated(unsafe) private static var count = 0

    /// How many lookups have reached the network layer since ``reset()``.
    static var requestCount: Int { lock.withLock { count } }

    /// How many of the next lookups should fail instead of answering.
    ///
    /// - Note: `nonisolated(unsafe)` because every access goes through ``lock``.
    nonisolated(unsafe) private static var failuresRemaining = 0

    /// Makes the next `count` lookups fail, so a test can watch what a failed lookup does to the
    /// cache.
    ///
    /// - Parameter count: How many lookups to fail.
    static func failNextLookups(_ count: Int) {
        lock.withLock { failuresRemaining = count }
    }

    /// Forgets every lookup counted so far.
    static func reset() {
        lock.withLock {
            count = 0
            wasMarked = false
            failuresRemaining = 0
        }
    }

    /// How long the stub takes to answer, which is what gives concurrent readers time to overlap.
    static let responseDelay: TimeInterval = 0.3

    /// Whether the most recent lookup carried ``ScytherOriginatedRequest``'s mark.
    ///
    /// Recorded rather than asserted inline because `startLoading()` runs on a thread the URL
    /// loading system owns.
    ///
    /// - Note: `nonisolated(unsafe)` because every access goes through ``lock``.
    nonisolated(unsafe) private static var wasMarked = false

    /// Whether the most recent lookup was marked as Scyther's own.
    static var lastRequestWasScytherOriginated: Bool { lock.withLock { wasMarked } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.ipify.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let shouldFail: Bool = Self.lock.withLock {
            Self.count += 1
            Self.wasMarked = ScytherOriginatedRequest.identifies(request)
            guard Self.failuresRemaining > 0 else { return false }
            Self.failuresRemaining -= 1
            return true
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.responseDelay) { [weak self] in
            guard let self, let url = request.url else { return }
            guard !shouldFail else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: url,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data("{\"ip\":\"203.0.113.9\"}".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { }
}

@MainActor
class ScytherNetworkHelperTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CountingIPAddressProtocol.reset()
        URLProtocol.registerClass(CountingIPAddressProtocol.self)
        NetworkHelper.instance.resetIPAddressCacheForTesting()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(CountingIPAddressProtocol.self)
        NetworkHelper.instance.resetIPAddressCacheForTesting()
        super.tearDown()
    }

    func testInit() {

    }

    /// The defect: ``NetworkHelper/ipAddress`` used to mark itself resolved only *after* the
    /// `await` returned, so the whole round trip was a window in which every arriving caller
    /// started a request of its own. A menu re-created once a second — which is what a modal
    /// presented over it does — therefore fired one lookup per second for as long as the first
    /// was outstanding.
    func testConcurrentReadersShareOneLookup() async {
        async let first = NetworkHelper.instance.ipAddress
        async let second = NetworkHelper.instance.ipAddress
        async let third = NetworkHelper.instance.ipAddress

        let resolved = await [first, second, third]

        XCTAssertEqual(resolved, ["203.0.113.9", "203.0.113.9", "203.0.113.9"],
                       "every caller gets the answer, not just the one that did the work")
        XCTAssertEqual(CountingIPAddressProtocol.requestCount, 1,
                       "one in-flight lookup is shared by every caller that arrives before it resolves")
    }

    /// Once resolved, the answer is cached and nothing goes out at all.
    func testALaterReaderIsAnsweredFromTheCache() async {
        _ = await NetworkHelper.instance.ipAddress
        XCTAssertEqual(CountingIPAddressProtocol.requestCount, 1)

        _ = await NetworkHelper.instance.ipAddress
        XCTAssertEqual(CountingIPAddressProtocol.requestCount, 1)
    }

    /// A failure is shared with everyone waiting on it, but not remembered.
    ///
    /// Coalescing changed the blast radius of a failed lookup: one failure now answers every
    /// caller waiting on it, where before each attempted its own. Caching that would turn a single
    /// blip into `0.0.0.0` on the menu until the app was relaunched, because the menu deliberately
    /// does not re-run the lookup when it reappears.
    func testAFailedLookupIsNotCached() async {
        CountingIPAddressProtocol.failNextLookups(1)

        async let first = NetworkHelper.instance.ipAddress
        async let second = NetworkHelper.instance.ipAddress
        let failed = await [first, second]

        XCTAssertEqual(failed, ["0.0.0.0", "0.0.0.0"], "the failure is shared, not raced")
        XCTAssertEqual(CountingIPAddressProtocol.requestCount, 1)

        let retried = await NetworkHelper.instance.ipAddress
        XCTAssertEqual(retried, "203.0.113.9", "the next caller tries again rather than reading the failure back")
        XCTAssertEqual(CountingIPAddressProtocol.requestCount, 2)
    }

    /// The lookup is Scyther's own, so no breakpoint, mock, rewrite or condition may touch it —
    /// which is what stops a breakpoint on `api.ipify.org` stalling the menu that sets it.
    func testTheLookupIsMarkedAsScythersOwn() async {
        _ = await NetworkHelper.instance.ipAddress
        XCTAssertTrue(CountingIPAddressProtocol.lastRequestWasScytherOriginated,
                      "the marker is what exempts the menu's own lookup from the menu's own tools")
    }
}
