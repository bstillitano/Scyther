//
//  Stack.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/12/20.
//

import Foundation

/// A generic last-in-first-out (LIFO) stack data structure.
///
/// `Stack` provides a simple array-backed implementation with push and pop operations.
/// Elements are added and removed from the top of the stack, following LIFO semantics.
///
/// ## Features
/// - **LIFO ordering**: The last element pushed is the first one popped
/// - **O(1) operations**: Push and pop are constant-time operations
/// - **Amortized growth**: Backed by a Swift array with automatic capacity management
///
/// ## Usage
/// ```swift
/// var myStack = Stack<Int>()
/// myStack.push(10)
/// myStack.push(3)
/// myStack.push(57)
/// myStack.pop() // returns 57
/// myStack.pop() // returns 3
/// myStack.top   // returns 10 without removing it
/// ```
public struct Stack<T> {

    /// Internal array storage for stack elements.
    var array = [T]()

    /// The number of elements in the stack.
    ///
    /// - Complexity: O(1)
    public var count: Int {
        return array.count
    }

    /// A Boolean value indicating whether the stack is empty.
    ///
    /// - Complexity: O(1)
    public var isEmpty: Bool {
        return array.isEmpty
    }

    /// Adds an element to the top of the stack.
    ///
    /// - Parameter element: The element to push onto the stack.
    /// - Complexity: O(1) amortized
    public mutating func push(_ element: T) {
        array.append(element)
    }

    /// Removes and returns the element at the top of the stack.
    ///
    /// - Returns: The element at the top of the stack, or `nil` if the stack is empty.
    /// - Complexity: O(1)
    public mutating func pop() -> T? {
        return array.popLast()
    }

    /// The element at the top of the stack, without removing it.
    ///
    /// This operation is also known as "peek".
    ///
    /// - Complexity: O(1)
    public var top: T? {
        return array.last
    }

    /// Removes all elements from the stack.
    ///
    /// - Complexity: O(*n*) where *n* is the number of elements in the stack.
    public mutating func clear() {
        self.array.removeAll()
    }

    /// A Boolean value indicating whether the stack contains one or more elements.
    ///
    /// - Complexity: O(1)
    public var isNotEmpty: Bool {
        return !self.array.isEmpty
    }
}
