//
//  GraphQLOperationTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class GraphQLOperationTests: XCTestCase {

    private func body(_ string: String) -> Data { string.data(using: .utf8)! }

    // MARK: - Detection

    func testNamedQueryByBodyShape() {
        let data = body(#"{"operationName":"GetUser","query":"query GetUser { me { id } }","variables":{"id":"1"}}"#)
        let op = GraphQLOperation.parse(body: data, url: "https://api.example.com/v1")
        XCTAssertNotNil(op)
        XCTAssertEqual(op?.operationName, "GetUser")
        XCTAssertEqual(op?.type, .query)
        XCTAssertFalse(op?.isBatch ?? true)
        XCTAssertEqual(op?.variables?["id"] as? String, "1")
    }

    func testOperationNameFieldTakesPrecedenceOverDocumentName() {
        let data = body(#"{"operationName":"Explicit","query":"query Document { a }"}"#)
        XCTAssertEqual(GraphQLOperation.parse(body: data, url: nil)?.operationName, "Explicit")
    }

    func testNameParsedFromDocumentWhenNoOperationNameField() {
        let data = body(#"{"query":"mutation UpdateAvatar($f:Upload!) { upload(f:$f) }"}"#)
        let op = GraphQLOperation.parse(body: data, url: nil)
        XCTAssertEqual(op?.operationName, "UpdateAvatar")
        XCTAssertEqual(op?.type, .mutation)
    }

    func testSubscriptionType() {
        let data = body(#"{"query":"subscription OnPing { ping }"}"#)
        XCTAssertEqual(GraphQLOperation.parse(body: data, url: nil)?.type, .subscription)
    }

    func testAnonymousShorthandQuery() {
        let data = body(#"{"query":"{ me { id } }"}"#)
        let op = GraphQLOperation.parse(body: data, url: nil)
        XCTAssertEqual(op?.operationName, "(anonymous)")
        XCTAssertEqual(op?.type, .query)
    }

    func testNamedQueryKeywordButNoName() {
        let data = body(#"{"query":"query { me { id } }"}"#)
        XCTAssertEqual(GraphQLOperation.parse(body: data, url: nil)?.operationName, "(anonymous)")
    }

    func testPathHintDetectsWhenNoQueryField() {
        // No "query" field, but the path says graphql and the body is JSON.
        let data = body(#"{"persistedQuery":{"sha256Hash":"abc"}}"#)
        let op = GraphQLOperation.parse(body: data, url: "https://api.example.com/graphql")
        XCTAssertNotNil(op)
        XCTAssertEqual(op?.operationName, "(anonymous)")
    }

    func testBatchedOperations() {
        let data = body(#"[{"query":"query A { a }"},{"query":"query B { b }"}]"#)
        let op = GraphQLOperation.parse(body: data, url: "https://api.example.com/graphql")
        XCTAssertEqual(op?.isBatch, true)
        XCTAssertEqual(op?.batchCount, 2)
        XCTAssertEqual(op?.operationName, "Batch (2 operations)")
        XCTAssertNil(op?.type)
    }

    // MARK: - Negative

    func testRestJSONIsNotGraphQL() {
        let data = body(#"{"name":"John","age":30}"#)
        XCTAssertNil(GraphQLOperation.parse(body: data, url: "https://api.example.com/users"))
    }

    func testNonJSONIsNotGraphQL() {
        XCTAssertNil(GraphQLOperation.parse(body: body("not json"), url: "https://api.example.com/x"))
    }

    func testEmptyBodyIsNotGraphQL() {
        XCTAssertNil(GraphQLOperation.parse(body: Data(), url: "https://api.example.com/x"))
        XCTAssertNil(GraphQLOperation.parse(body: nil, url: "https://api.example.com/x"))
    }

    // MARK: - Display helpers

    func testTypeDisplayHelpers() {
        XCTAssertEqual(GraphQLOperationType.query.displayName, "Query")
        XCTAssertEqual(GraphQLOperationType.mutation.badgeText, "MUTATION")
    }
}
