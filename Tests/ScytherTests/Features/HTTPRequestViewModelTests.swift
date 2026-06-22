//
//  HTTPRequestViewModelTests.swift
//  ScytherTests
//

@testable import Scyther
import SwiftUI
import XCTest

@MainActor
final class HTTPRequestViewModelTests: XCTestCase {

    func testGraphQLFieldsExposed() {
        let request = HTTPRequest()
        request.isGraphQL = true
        request.graphQLOperationName = "GetUser"
        request.graphQLOperationType = .query

        let viewModel = HTTPRequestViewModel(request: request)
        XCTAssertTrue(viewModel.isGraphQL)
        XCTAssertEqual(viewModel.operationName, "GetUser")
        XCTAssertEqual(viewModel.operationBadgeText, "QUERY")
        XCTAssertEqual(viewModel.operationBadgeColor, .green)
    }

    func testMutationBadgeColor() {
        let request = HTTPRequest()
        request.isGraphQL = true
        request.graphQLOperationType = .mutation
        XCTAssertEqual(HTTPRequestViewModel(request: request).operationBadgeColor, .orange)
    }

    func testNonGraphQLFallback() {
        let request = HTTPRequest()
        let viewModel = HTTPRequestViewModel(request: request)
        XCTAssertFalse(viewModel.isGraphQL)
        XCTAssertEqual(viewModel.operationName, "-")
        XCTAssertNil(viewModel.operationBadgeText)
    }
}
