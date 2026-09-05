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

    func testWasStubbedMirrorsTheCapture() {
        let stubbed = HTTPRequest()
        stubbed.wasStubbed = true
        XCTAssertTrue(HTTPRequestViewModel(request: stubbed).wasStubbed)
    }

    func testWasStubbedIsFalseForANetworkResponse() {
        XCTAssertFalse(HTTPRequestViewModel(request: HTTPRequest()).wasStubbed)
    }

    func testIsReplayMirrorsTheCapturedProvenance() {
        let replay = HTTPRequest()
        replay.replayOfID = "original-hash"
        XCTAssertTrue(HTTPRequestViewModel(request: replay).isReplay)
    }

    func testIsReplayIsFalseForTrafficTheAppMade() {
        XCTAssertFalse(HTTPRequestViewModel(request: HTTPRequest()).isReplay)
    }

    func testWasHeldMirrorsTheBreakpointsThatHeldIt() {
        let held = HTTPRequest()
        held.breakpointNames = ["cart"]
        XCTAssertTrue(HTTPRequestViewModel(request: held).wasHeld)
    }

    func testWasHeldIsFalseForTrafficNoBreakpointStopped() {
        XCTAssertFalse(HTTPRequestViewModel(request: HTTPRequest()).wasHeld)
    }

    func testNonGraphQLFallback() {
        let request = HTTPRequest()
        let viewModel = HTTPRequestViewModel(request: request)
        XCTAssertFalse(viewModel.isGraphQL)
        XCTAssertEqual(viewModel.operationName, "-")
        XCTAssertNil(viewModel.operationBadgeText)
    }
}
