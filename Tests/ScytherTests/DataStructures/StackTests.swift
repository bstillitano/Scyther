//
//  StackTests.swift
//  ScytherTests
//
//  Created by Brandon Stillitano on 21/12/2025.
//

@testable import Scyther
import XCTest

final class StackTests: XCTestCase {

    // MARK: - Initialization Tests

    func testEmptyStackInitialization() {
        let stack = Stack<Int>()
        XCTAssertTrue(stack.isEmpty)
        XCTAssertEqual(stack.count, 0)
        XCTAssertNil(stack.top)
    }

    // MARK: - Push Tests

    func testPushSingleElement() {
        var stack = Stack<Int>()
        stack.push(10)
        XCTAssertFalse(stack.isEmpty)
        XCTAssertEqual(stack.count, 1)
        XCTAssertEqual(stack.top, 10)
    }

    func testPushMultipleElements() {
        var stack = Stack<Int>()
        stack.push(10)
        stack.push(20)
        stack.push(30)
        XCTAssertEqual(stack.count, 3)
        XCTAssertEqual(stack.top, 30)
    }

    // MARK: - Pop Tests

    func testPopFromNonEmptyStack() {
        var stack = Stack<Int>()
        stack.push(10)
        stack.push(20)
        stack.push(30)

        let popped = stack.pop()
        XCTAssertEqual(popped, 30)
        XCTAssertEqual(stack.count, 2)
        XCTAssertEqual(stack.top, 20)
    }

    func testPopFromEmptyStack() {
        var stack = Stack<Int>()
        let popped = stack.pop()
        XCTAssertNil(popped)
    }

    func testPopAllElements() {
        var stack = Stack<Int>()
        stack.push(1)
        stack.push(2)
        stack.push(3)

        XCTAssertEqual(stack.pop(), 3)
        XCTAssertEqual(stack.pop(), 2)
        XCTAssertEqual(stack.pop(), 1)
        XCTAssertNil(stack.pop())
        XCTAssertTrue(stack.isEmpty)
    }

    // MARK: - Top (Peek) Tests

    func testTopDoesNotRemoveElement() {
        var stack = Stack<Int>()
        stack.push(10)
        stack.push(20)

        XCTAssertEqual(stack.top, 20)
        XCTAssertEqual(stack.count, 2)
        XCTAssertEqual(stack.top, 20)  // Still 20
    }

    func testTopOnEmptyStack() {
        let stack = Stack<Int>()
        XCTAssertNil(stack.top)
    }

    // MARK: - Clear Tests

    func testClear() {
        var stack = Stack<Int>()
        stack.push(1)
        stack.push(2)
        stack.push(3)

        stack.clear()
        XCTAssertTrue(stack.isEmpty)
        XCTAssertEqual(stack.count, 0)
        XCTAssertNil(stack.top)
    }

    func testClearEmptyStack() {
        var stack = Stack<Int>()
        stack.clear()
        XCTAssertTrue(stack.isEmpty)
    }

    // MARK: - isEmpty Tests

    func testIsEmptyTrue() {
        let stack = Stack<Int>()
        XCTAssertTrue(stack.isEmpty)
    }

    func testIsEmptyFalse() {
        var stack = Stack<Int>()
        stack.push(1)
        XCTAssertFalse(stack.isEmpty)
    }

    // MARK: - isNotEmpty Tests

    func testIsNotEmptyTrue() {
        var stack = Stack<Int>()
        stack.push(1)
        XCTAssertTrue(stack.isNotEmpty)
    }

    func testIsNotEmptyFalse() {
        let stack = Stack<Int>()
        XCTAssertFalse(stack.isNotEmpty)
    }

    // MARK: - Count Tests

    func testCount() {
        var stack = Stack<Int>()
        XCTAssertEqual(stack.count, 0)

        stack.push(1)
        XCTAssertEqual(stack.count, 1)

        stack.push(2)
        XCTAssertEqual(stack.count, 2)

        _ = stack.pop()
        XCTAssertEqual(stack.count, 1)
    }

    // MARK: - LIFO Order Tests

    func testLIFOOrder() {
        var stack = Stack<String>()
        stack.push("first")
        stack.push("second")
        stack.push("third")

        XCTAssertEqual(stack.pop(), "third")
        XCTAssertEqual(stack.pop(), "second")
        XCTAssertEqual(stack.pop(), "first")
    }

    // MARK: - Different Types Tests

    func testWithStrings() {
        var stack = Stack<String>()
        stack.push("Hello")
        stack.push("World")

        XCTAssertEqual(stack.top, "World")
        XCTAssertEqual(stack.pop(), "World")
        XCTAssertEqual(stack.pop(), "Hello")
    }

    func testWithOptionals() {
        var stack = Stack<Int?>()
        stack.push(nil)
        stack.push(42)

        XCTAssertEqual(stack.pop(), 42)
        // When T is Int?, pop() returns Int?? - we need to unwrap and check for nil
        let poppedValue = stack.pop()
        XCTAssertNotNil(poppedValue)  // The Optional wrapper is not nil
        XCTAssertNil(poppedValue!)     // The inner value is nil
    }

    func testWithStructs() {
        struct TestStruct: Equatable {
            let id: Int
            let name: String
        }

        var stack = Stack<TestStruct>()
        stack.push(TestStruct(id: 1, name: "First"))
        stack.push(TestStruct(id: 2, name: "Second"))

        XCTAssertEqual(stack.top, TestStruct(id: 2, name: "Second"))
    }
}
