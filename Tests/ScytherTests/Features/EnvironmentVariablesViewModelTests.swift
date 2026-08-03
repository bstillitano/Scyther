//
//  EnvironmentVariablesViewModelTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 3/8/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

@MainActor
final class EnvironmentVariablesViewModelTests: XCTestCase {

    private func makeViewModel(variables: [String: String]) async -> EnvironmentVariablesViewModel {
        Scyther.environmentVariables = variables
        let viewModel = EnvironmentVariablesViewModel()
        await viewModel.onFirstAppear()
        return viewModel
    }

    override func tearDown() {
        Scyther.environmentVariables = [:]
        super.tearDown()
    }

    func testVariablesAreSortedByKey() async {
        let viewModel = await makeViewModel(variables: [
            "FEATURE_NEW_UI": "enabled",
            "API_BASE_URL": "https://api.example.com"
        ])

        XCTAssertEqual(viewModel.variables.map(\.key), ["API_BASE_URL", "FEATURE_NEW_UI"])
    }

    func testEmptyQueryReturnsAllVariables() async {
        let viewModel = await makeViewModel(variables: ["A": "1", "B": "2"])

        XCTAssertEqual(viewModel.filteredVariables.count, 2)
    }

    func testFilteringMatchesKeys() async {
        let viewModel = await makeViewModel(variables: [
            "API_BASE_URL": "https://api.example.com",
            "FEATURE_NEW_UI": "enabled"
        ])

        viewModel.searchText = "base url"
        XCTAssertEqual(viewModel.filteredVariables.map(\.key), ["API_BASE_URL"])
    }

    func testFilteringMatchesValues() async {
        let viewModel = await makeViewModel(variables: [
            "APP_ENVIRONMENT": "development",
            "FEATURE_NEW_UI": "enabled"
        ])

        viewModel.searchText = "development"
        XCTAssertEqual(viewModel.filteredVariables.map(\.key), ["APP_ENVIRONMENT"])
    }

    func testFilteringIsCaseInsensitive() async {
        let viewModel = await makeViewModel(variables: ["API_BASE_URL": "https://api.example.com"])

        viewModel.searchText = "api_base"
        XCTAssertEqual(viewModel.filteredVariables.count, 1)
    }

    func testWhitespaceQueryReturnsAllVariables() async {
        let viewModel = await makeViewModel(variables: ["A": "1"])

        viewModel.searchText = "   "
        XCTAssertEqual(viewModel.filteredVariables.count, 1)
    }

    func testUnmatchedQueryReturnsNothing() async {
        let viewModel = await makeViewModel(variables: ["A": "1"])

        viewModel.searchText = "zzz"
        XCTAssertTrue(viewModel.filteredVariables.isEmpty)
    }
}
#endif
