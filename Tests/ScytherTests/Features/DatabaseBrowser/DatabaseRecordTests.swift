//
//  DatabaseRecordTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class DatabaseRecordTests: XCTestCase {

    // MARK: - Initialization Tests

    func testRecordInitialization() {
        let values: [String: DatabaseValue] = [
            "id": .integer(1),
            "name": .text("Test"),
            "price": .real(9.99)
        ]
        let record = DatabaseRecord(
            tableName: "products",
            primaryKey: .integer(1),
            primaryKeyColumn: "id",
            values: values
        )

        XCTAssertEqual(record.tableName, "products")
        XCTAssertEqual(record.values.count, 3)
        XCTAssertEqual(record.primaryKeyColumn, "id")
    }

    func testRecordWithoutPrimaryKey() {
        let values: [String: DatabaseValue] = [
            "name": .text("Test")
        ]
        let record = DatabaseRecord(
            tableName: "items",
            primaryKey: nil,
            primaryKeyColumn: nil,
            values: values
        )

        XCTAssertNil(record.primaryKeyColumn)
        XCTAssertNil(record.primaryKey)
    }

    // MARK: - Primary Key Tests

    func testPrimaryKeyExtraction() {
        let values: [String: DatabaseValue] = [
            "id": .integer(42),
            "name": .text("Test")
        ]
        let record = DatabaseRecord(
            tableName: "users",
            primaryKey: .integer(42),
            primaryKeyColumn: "id",
            values: values
        )

        XCTAssertEqual(record.primaryKey, .integer(42))
    }

    // MARK: - Display Value Tests

    func testDisplayValueForExistingColumn() {
        let values: [String: DatabaseValue] = [
            "name": .text("Hello")
        ]
        let record = DatabaseRecord(tableName: "test", values: values)

        XCTAssertEqual(record.displayValue(for: "name"), "Hello")
    }

    func testDisplayValueForMissingColumn() {
        let values: [String: DatabaseValue] = [
            "name": .text("Hello")
        ]
        let record = DatabaseRecord(tableName: "test", values: values)

        XCTAssertEqual(record.displayValue(for: "missing"), "NULL")
    }

    // MARK: - Column Sorting Tests

    func testSortedColumnNames() {
        let values: [String: DatabaseValue] = [
            "zebra": .text("z"),
            "apple": .text("a"),
            "mango": .text("m")
        ]
        let record = DatabaseRecord(tableName: "test", values: values)

        let sorted = record.sortedColumnNames
        XCTAssertEqual(sorted, ["apple", "mango", "zebra"])
    }

    // MARK: - Identifiable Tests

    func testRecordHasUniqueId() {
        let values: [String: DatabaseValue] = ["name": .text("Test")]
        let record1 = DatabaseRecord(tableName: "test", values: values)
        let record2 = DatabaseRecord(tableName: "test", values: values)

        XCTAssertNotEqual(record1.id, record2.id)
    }
}
#endif
