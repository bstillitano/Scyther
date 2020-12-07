//
//  Stack.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/12/20.
//

import Foundation

/**
  Stack
  A stack is like an array but with limited functionality. You can only push
  to add a new element to the top of the stack, pop to remove the element from
  the top, and peek at the top element without popping it off.
  A stack gives you a LIFO or last-in first-out order. The element you pushed
  last is the first one to come off with the next pop.
  Push and pop are O(1) operations.
 
  ## Usage
  ```
  var myStack = Stack(array: [])
  myStack.push(10)
  myStack.push(3)
  myStack.push(57)
  myStack.pop() // 57
  myStack.pop() // 3
 ```
*/
public struct Stack<T> {

    /**
     Data structure consisiting of a generic item
    */
    var array = [T]()

    /**
     Indicates the number of values contained within the `array` object.
    */
    public var count: Int {
        return array.count
    }

    /**
     Indicates whether or not the `array` object contains zero (0) values.
    */
    public var isEmpty: Bool {
        return array.isEmpty
    }

    /**
     Pushes an item to the top of the stack.
     
     - Parameter element: The item being pushed.
     */
    public mutating func push(_ element: T) {
        array.append(element)
    }

    /**
     Removes and returns the item at the top of the stack.
     
     - Returns: The item at the top of the stack.
     */
    public mutating func pop() -> T? {
        return array.popLast()
    }

    /**
     Returns the item at the top of the stack. This is otherwise known as `peek`.
     */
    public var top: T? {
        return array.last
    }

    public mutating func clear() {
        self.array.removeAll()
    }

    /**
     Indicates whether or not the `array` object contains zero (0) values.
     */
    public var isNotEmpty: Bool {
        return !self.array.isEmpty
    }
}
