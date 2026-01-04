//
//  TableInfoTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 4/1/2026.
//

#if !os(macOS)
@testable import Scyther
import XCTest

final class TableInfoTests: XCTestCase {

    // MARK: - TableInfo Tests

    func testTableInfoInitialization() {
        let table = TableInfo(name: "users", isView: false)

        XCTAssertEqual(table.name, "users")
        XCTAssertFalse(table.isView)
    }

    func testTableInfoAsView() {
        let view = TableInfo(name: "user_summary", isView: true)

        XCTAssertEqual(view.name, "user_summary")
        XCTAssertTrue(view.isView)
    }

    func testTableInfoIdentifiable() {
        let table = TableInfo(name: "users", isView: false)

        // Tables should have a valid UUID id
        XCTAssertNotNil(table.id)
    }

    func testTableInfoDifferentInstancesHaveDifferentIds() {
        let table1 = TableInfo(name: "users", isView: false)
        let table2 = TableInfo(name: "users", isView: false)

        // Different instances have different UUIDs
        XCTAssertNotEqual(table1.id, table2.id)
    }
}

// MARK: - ColumnInfo Tests

final class ColumnInfoTests: XCTestCase {

    func testColumnInfoInitialization() {
        let column = ColumnInfo(
            name: "id",
            type: "INTEGER",
            isPrimaryKey: true,
            isNullable: false,
            defaultValue: nil
        )

        XCTAssertEqual(column.name, "id")
        XCTAssertEqual(column.type, "INTEGER")
        XCTAssertTrue(column.isPrimaryKey)
        XCTAssertFalse(column.isNullable)
        XCTAssertNil(column.defaultValue)
    }

    func testNullableColumn() {
        let column = ColumnInfo(
            name: "email",
            type: "TEXT",
            isPrimaryKey: false,
            isNullable: true,
            defaultValue: nil
        )

        XCTAssertTrue(column.isNullable)
        XCTAssertFalse(column.isPrimaryKey)
    }

    func testColumnWithDefaultValue() {
        let column = ColumnInfo(
            name: "active",
            type: "INTEGER",
            isPrimaryKey: false,
            isNullable: false,
            defaultValue: "1"
        )

        XCTAssertEqual(column.defaultValue, "1")
    }

    func testColumnIdentifiable() {
        let column = ColumnInfo(name: "id", type: "INTEGER", isPrimaryKey: true)

        XCTAssertNotNil(column.id)
    }
}

// MARK: - TableSchema Tests

final class TableSchemaTests: XCTestCase {

    func testTableSchemaInitialization() {
        let columns = [
            ColumnInfo(name: "id", type: "INTEGER", isPrimaryKey: true, isNullable: false),
            ColumnInfo(name: "name", type: "TEXT", isPrimaryKey: false, isNullable: true)
        ]
        let schema = TableSchema(tableName: "users", columns: columns, foreignKeys: [], indexes: [])

        XCTAssertEqual(schema.tableName, "users")
        XCTAssertEqual(schema.columns.count, 2)
        XCTAssertTrue(schema.foreignKeys.isEmpty)
        XCTAssertTrue(schema.indexes.isEmpty)
    }

    func testSchemaWithForeignKey() {
        let columns = [
            ColumnInfo(name: "user_id", type: "INTEGER", isPrimaryKey: false, isNullable: false)
        ]
        let foreignKeys = [
            ForeignKeyInfo(column: "user_id", referencedTable: "users", referencedColumn: "id")
        ]
        let schema = TableSchema(tableName: "posts", columns: columns, foreignKeys: foreignKeys, indexes: [])

        XCTAssertEqual(schema.foreignKeys.count, 1)
        XCTAssertEqual(schema.foreignKeys.first?.column, "user_id")
        XCTAssertEqual(schema.foreignKeys.first?.referencedTable, "users")
    }

    func testSchemaWithIndex() {
        let columns = [
            ColumnInfo(name: "email", type: "TEXT", isPrimaryKey: false, isNullable: false)
        ]
        let indexes = [
            IndexInfo(name: "idx_email", isUnique: true, columns: ["email"])
        ]
        let schema = TableSchema(tableName: "users", columns: columns, foreignKeys: [], indexes: indexes)

        XCTAssertEqual(schema.indexes.count, 1)
        XCTAssertTrue(schema.indexes.first?.isUnique ?? false)
    }

    func testPrimaryKeyColumn() {
        let columns = [
            ColumnInfo(name: "id", type: "INTEGER", isPrimaryKey: true, isNullable: false),
            ColumnInfo(name: "name", type: "TEXT", isPrimaryKey: false, isNullable: true)
        ]
        let schema = TableSchema(tableName: "users", columns: columns)

        XCTAssertNotNil(schema.primaryKeyColumn)
        XCTAssertEqual(schema.primaryKeyColumn?.name, "id")
    }
}

// MARK: - ForeignKeyInfo Tests

final class ForeignKeyInfoTests: XCTestCase {

    func testForeignKeyInfoInitialization() {
        let fk = ForeignKeyInfo(column: "user_id", referencedTable: "users", referencedColumn: "id")

        XCTAssertEqual(fk.column, "user_id")
        XCTAssertEqual(fk.referencedTable, "users")
        XCTAssertEqual(fk.referencedColumn, "id")
    }

    func testForeignKeyIdentifiable() {
        let fk = ForeignKeyInfo(column: "user_id", referencedTable: "users", referencedColumn: "id")

        XCTAssertNotNil(fk.id)
    }
}

// MARK: - IndexInfo Tests

final class IndexInfoTests: XCTestCase {

    func testIndexInfoInitialization() {
        let index = IndexInfo(name: "idx_users_email", isUnique: true, columns: ["email"])

        XCTAssertEqual(index.name, "idx_users_email")
        XCTAssertEqual(index.columns, ["email"])
        XCTAssertTrue(index.isUnique)
    }

    func testNonUniqueIndex() {
        let index = IndexInfo(name: "idx_created_at", isUnique: false, columns: ["created_at"])

        XCTAssertFalse(index.isUnique)
    }

    func testCompoundIndex() {
        let index = IndexInfo(name: "idx_compound", isUnique: false, columns: ["first_name", "last_name"])

        XCTAssertEqual(index.columns.count, 2)
    }
}
#endif
