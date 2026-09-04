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

    func testCurlRequestPopulatedOnFirstAppear() async {
        let request = HTTPRequest()
        request.requestCurl = "curl -X GET 'https://api.example.com/users'"

        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()

        XCTAssertEqual(viewModel.curlRequest, "curl -X GET 'https://api.example.com/users'")
    }

    func testCurlRequestDefaultsToEmptyWhenMissing() async {
        let request = HTTPRequest()
        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()
        XCTAssertEqual(viewModel.curlRequest, "")
    }

    func testNonGraphQLHasNoGraphQLSection() async {
        let request = HTTPRequest()
        let viewModel = LogDetailsViewModel(httpRequest: request)
        await viewModel.onFirstAppear()
        XCTAssertFalse(viewModel.hasGraphQL)
    }
}
