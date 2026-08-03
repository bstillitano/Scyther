//
//  CookieBrowserViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 3/8/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

@MainActor
final class CookieBrowserViewModelTests: XCTestCase {

    /// Builds a cookie item without touching `HTTPCookieStorage`, so these tests
    /// have no shared-state side effects.
    private func item(name: String, domain: String, value: String) -> CookieItem {
        let cookie = HTTPCookie(properties: [
            .name: name,
            .domain: domain,
            .path: "/",
            .value: value
        ])!
        return CookieItem(name: cookie.name, domain: cookie.domain, cookie: cookie)
    }

    private func makeViewModel() -> CookieBrowserViewModel {
        let viewModel = CookieBrowserViewModel()
        viewModel.cookies = [
            item(name: "auth_token", domain: "api.example.com", value: "abc123"),
            item(name: "session_id", domain: "example.com", value: "xyz789")
        ]
        return viewModel
    }

    func testEmptyQueryReturnsAllCookies() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.filteredCookies.count, 2)
    }

    func testWhitespaceQueryReturnsAllCookies() {
        let viewModel = makeViewModel()
        viewModel.searchText = "   "
        XCTAssertEqual(viewModel.filteredCookies.count, 2)
    }

    func testFilteringMatchesNames() {
        let viewModel = makeViewModel()
        viewModel.searchText = "session"
        XCTAssertEqual(viewModel.filteredCookies.map(\.name), ["session_id"])
    }

    func testFilteringTreatsUnderscoresAsSpaces() {
        let viewModel = makeViewModel()
        viewModel.searchText = "auth token"
        XCTAssertEqual(viewModel.filteredCookies.map(\.name), ["auth_token"])
    }

    func testFilteringMatchesDomains() {
        let viewModel = makeViewModel()
        viewModel.searchText = "api.example"
        XCTAssertEqual(viewModel.filteredCookies.map(\.name), ["auth_token"])
    }

    func testFilteringMatchesValues() {
        let viewModel = makeViewModel()
        viewModel.searchText = "xyz789"
        XCTAssertEqual(viewModel.filteredCookies.map(\.name), ["session_id"])
    }

    func testUnmatchedQueryReturnsNothing() {
        let viewModel = makeViewModel()
        viewModel.searchText = "zzz"
        XCTAssertTrue(viewModel.filteredCookies.isEmpty)
    }
}
#endif
