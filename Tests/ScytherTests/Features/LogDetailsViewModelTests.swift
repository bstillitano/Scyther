//
//  LogDetailsViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

@MainActor
final class LogDetailsViewModelTests: XCTestCase {

    func testGraphQLFieldsPopulatedOnFirstAppear() async {
        let request = HTTPRequest()
        request.isGraphQL = true
        request.graphQLOperationName = "GetUser"
        request.graphQLOperationType = .mutation

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertTrue(viewModel.hasGraphQL)
        XCTAssertEqual(viewModel.graphQLOperationName, "GetUser")
        XCTAssertEqual(viewModel.graphQLOperationType, "Mutation")
    }

    func testNonGraphQLHasNoGraphQLSection() async {
        let request = HTTPRequest()
        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()
        XCTAssertFalse(viewModel.hasGraphQL)
    }
}
