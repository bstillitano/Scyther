//
//  NetworkRuleHeaderFieldTests.swift
//  ScytherTests
//

@testable import Scyther
import XCTest

final class NetworkRuleHeaderFieldTests: XCTestCase {

    // MARK: - One row

    func testARowWithOnlyWhitespaceIsNotNamed() {
        XCTAssertFalse(NetworkRuleHeaderField(name: "   \n").isNamed)
        XCTAssertFalse(NetworkRuleHeaderField().isNamed)
        XCTAssertTrue(NetworkRuleHeaderField(name: "Authorization").isNamed)
    }

    func testTrimmedNameDropsSurroundingWhitespace() {
        XCTAssertEqual(NetworkRuleHeaderField(name: "  Authorization \n").trimmedName, "Authorization")
    }

    func testARowKeepsItsIdentityWhileItsNameChanges() {
        let id = UUID()
        var field = NetworkRuleHeaderField(id: id, name: "Auth")
        field.name = "Authorization"
        XCTAssertEqual(field.id, id, "a row that changed identity mid-edit would lose keyboard focus")
    }

    // MARK: - Folding rows into a rule

    func testUnnamedRowsAreDroppedFromTheDictionary() {
        let fields = [
            NetworkRuleHeaderField(name: "Content-Type", value: "application/json"),
            NetworkRuleHeaderField(name: "  ", value: "orphaned"),
            NetworkRuleHeaderField()
        ]
        XCTAssertEqual(fields.headerDictionary, ["Content-Type": "application/json"])
    }

    func testNamesAreTrimmedIntoTheDictionary() {
        let fields = [NetworkRuleHeaderField(name: " Accept ", value: "*/*")]
        XCTAssertEqual(fields.headerDictionary, ["Accept": "*/*"])
    }

    func testTheLastRowWinsANameCollision() {
        let fields = [
            NetworkRuleHeaderField(name: "Accept", value: "first"),
            NetworkRuleHeaderField(name: "Accept", value: "second")
        ]
        XCTAssertEqual(
            fields.headerDictionary,
            ["Accept": "second"],
            "the last row the developer typed is the one they can see, so it must be the one that survives"
        )
    }

    func testAnEmptyListFoldsToAnEmptyDictionary() {
        XCTAssertTrue([NetworkRuleHeaderField]().headerDictionary.isEmpty)
    }

    func testHeaderNamesKeepRowOrderAndDropUnnamedRows() {
        let fields = [
            NetworkRuleHeaderField(name: " Set-Cookie "),
            NetworkRuleHeaderField(name: ""),
            NetworkRuleHeaderField(name: "Authorization")
        ]
        XCTAssertEqual(fields.headerNames, ["Set-Cookie", "Authorization"])
    }

    func testHeaderNamesKeepsADuplicateName() {
        let fields = [NetworkRuleHeaderField(name: "Accept"), NetworkRuleHeaderField(name: "Accept")]
        XCTAssertEqual(
            fields.headerNames,
            ["Accept", "Accept"],
            "the remove list is an ordered list of names, not a set, so it must not collapse duplicates"
        )
    }

    // MARK: - Building rows from a rule

    func testRowsBuiltFromADictionaryAreOrderedByName() {
        let fields = [NetworkRuleHeaderField].fields(from: [
            "Set-Cookie": "a=1",
            "Accept": "*/*",
            "Content-Type": "application/json"
        ])
        XCTAssertEqual(
            fields.map(\.name),
            ["Accept", "Content-Type", "Set-Cookie"],
            "a dictionary has no order, so the rows must impose one or the list reshuffles per launch"
        )
        XCTAssertEqual(fields.map(\.value), ["*/*", "application/json", "a=1"])
    }

    func testRowsBuiltFromAnEmptyDictionaryAreEmpty() {
        XCTAssertTrue([NetworkRuleHeaderField].fields(from: [String: String]()).isEmpty)
    }

    func testRowsBuiltFromNamesKeepTheirOrderAndCarryNoValue() {
        let fields = [NetworkRuleHeaderField].fields(from: ["Set-Cookie", "Authorization"])
        XCTAssertEqual(fields.map(\.name), ["Set-Cookie", "Authorization"])
        XCTAssertEqual(fields.map(\.value), ["", ""])
    }

    func testRowsBuiltFromNamesCarryDistinctIdentities() {
        let fields = [NetworkRuleHeaderField].fields(from: ["Accept", "Accept"])
        XCTAssertNotEqual(fields.first?.id, fields.last?.id)
    }

    func testADictionaryRoundTripsThroughRows() {
        let headers = ["Accept": "*/*", "Content-Type": "application/json"]
        XCTAssertEqual([NetworkRuleHeaderField].fields(from: headers).headerDictionary, headers)
    }
}
