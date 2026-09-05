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

    /// A header rewrite or a condition shapes a request that still goes out, so without a badge of
    /// its own the row is indistinguishable from traffic nobody touched.
    func testARewrittenRequestIsMarkedOverridden() {
        let rewritten = HTTPRequest()
        rewritten.appliedRuleNames = ["Swap the auth token"]
        XCTAssertTrue(HTTPRequestViewModel(request: rewritten).wasOverridden)
    }

    /// A stub already says so with its own badge, so it does not also wear this one.
    func testAStubbedRequestIsNotAlsoMarkedOverridden() {
        let stubbed = HTTPRequest()
        stubbed.wasStubbed = true
        stubbed.appliedRuleNames = ["Empty cart"]
        let viewModel = HTTPRequestViewModel(request: stubbed)
        XCTAssertTrue(viewModel.wasStubbed)
        XCTAssertFalse(viewModel.wasOverridden, "MOCKED already says what happened")
    }

    func testUntouchedTrafficIsNotMarkedOverridden() {
        XCTAssertFalse(HTTPRequestViewModel(request: HTTPRequest()).wasOverridden)
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
