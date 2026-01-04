//
//  QueryResultTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class QueryResultTests: XCTestCase {

    // MARK: - Initialization Tests

    func testQueryResultInitialization() {
        let result = QueryResult(
            columns: ["id", "name"],
            rows: [],
            rowsAffected: 0,
            isReadOnly: true,
            executionTime: 0.001
        )

        XCTAssertEqual(result.columns.count, 2)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.rowsAffected, 0)
        XCTAssertTrue(result.isReadOnly)
    }

    func testQueryResultWithRows() {
        let rows: [[String: DatabaseValue]] = [
            ["id": .integer(1), "name": .text("Alice")],
            ["id": .integer(2), "name": .text("Bob")]
        ]
        let result = QueryResult(
            columns: ["id", "name"],
            rows: rows,
            rowsAffected: 0,
            isReadOnly: true,
            executionTime: nil
        )

        XCTAssertEqual(result.rows.count, 2)
    }

    func testNonReadOnlyResult() {
        let result = QueryResult(
            columns: [],
            rows: [],
            rowsAffected: 5,
            isReadOnly: false,
            executionTime: 0.002
        )

        XCTAssertFalse(result.isReadOnly)
        XCTAssertEqual(result.rowsAffected, 5)
    }

    func testExecutionTime() {
        let result = QueryResult(
            columns: [],
            rows: [],
            rowsAffected: 0,
            isReadOnly: true,
            executionTime: 0.0123
        )

        XCTAssertEqual(result.executionTime, 0.0123)
    }

    func testNilExecutionTime() {
        let result = QueryResult(
            columns: [],
            rows: [],
            rowsAffected: 0,
            isReadOnly: true,
            executionTime: nil
        )

        XCTAssertNil(result.executionTime)
    }
}

// MARK: - DatabaseType Tests

final class DatabaseTypeTests: XCTestCase {

    func testSQLiteType() {
        let type = DatabaseType.sqlite
        XCTAssertEqual(type.displayName, "SQLite")
        XCTAssertEqual(type.iconName, "cylinder.fill")
    }

    func testCoreDataType() {
        let type = DatabaseType.coreData
        XCTAssertEqual(type.displayName, "Core Data")
        XCTAssertEqual(type.iconName, "square.stack.3d.up.fill")
    }

    func testSwiftDataType() {
        let type = DatabaseType.swiftData
        XCTAssertEqual(type.displayName, "SwiftData")
        XCTAssertEqual(type.iconName, "swift")
    }

    func testCustomType() {
        let type = DatabaseType.custom("Realm")
        XCTAssertEqual(type.displayName, "Realm")
        XCTAssertEqual(type.iconName, "externaldrive.fill")
    }

    func testCustomTypeWithDifferentName() {
        let type = DatabaseType.custom("Firebase")
        XCTAssertEqual(type.displayName, "Firebase")
    }
}

// MARK: - DatabaseBrowserError Tests

final class DatabaseBrowserErrorTests: XCTestCase {

    func testConnectionFailedError() {
        let error = DatabaseBrowserError.connectionFailed("Test reason")
        XCTAssertEqual(error.errorDescription, "Connection failed: Test reason")
    }

    func testQueryFailedError() {
        let error = DatabaseBrowserError.queryFailed("Syntax error")
        XCTAssertEqual(error.errorDescription, "Query failed: Syntax error")
    }

    func testTableNotFoundError() {
        let error = DatabaseBrowserError.tableNotFound("users")
        XCTAssertEqual(error.errorDescription, "Table not found: users")
    }

    func testWriteNotSupportedError() {
        let error = DatabaseBrowserError.writeNotSupported
        XCTAssertEqual(error.errorDescription, "Write operations are not supported by this database")
    }

    func testRecordNotFoundError() {
        let error = DatabaseBrowserError.recordNotFound
        XCTAssertEqual(error.errorDescription, "Record not found")
    }

    func testInvalidPrimaryKeyError() {
        let error = DatabaseBrowserError.invalidPrimaryKey
        XCTAssertEqual(error.errorDescription, "Invalid or missing primary key")
    }

    func testGeneralError() {
        let error = DatabaseBrowserError.general("Something went wrong")
        XCTAssertEqual(error.errorDescription, "Something went wrong")
    }
}
#endif
