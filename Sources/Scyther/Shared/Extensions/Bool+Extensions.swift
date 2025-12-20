//
//  Bool+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import Foundation

/// Provides convenient extensions for Boolean values including string conversion and compound assignment operators.
///
/// This extension adds utility methods and operators to make working with Boolean values more convenient,
/// including string representation and logical compound assignment operators similar to those available
/// for numeric types.
extension Bool {
    /// A string representation of the Boolean value.
    ///
    /// Returns `"true"` for `true` and `"false"` for `false`.
    ///
    /// ## Example
    /// ```swift
    /// let flag = true
    /// print(flag.stringValue) // Prints "true"
    ///
    /// let disabled = false
    /// print(disabled.stringValue) // Prints "false"
    /// ```
    var stringValue: String {
        return self ? "true" : "false"
    }

    /// Performs a logical OR operation and assigns the result to the left-hand side variable.
    ///
    /// This operator is equivalent to `leftSide = leftSide || rightSide`.
    ///
    /// - Parameters:
    ///   - leftSide: The Boolean variable to modify
    ///   - rightSide: The Boolean value to OR with the left side
    ///
    /// ## Example
    /// ```swift
    /// var hasError = false
    /// hasError |= true  // hasError is now true
    /// hasError |= false // hasError remains true
    /// ```
    static public func |= (leftSide: inout Bool, rightSide: Bool) {
        leftSide = leftSide || rightSide
    }

    /// Performs a logical AND operation and assigns the result to the left-hand side variable.
    ///
    /// This operator is equivalent to `leftSide = leftSide && rightSide`.
    ///
    /// - Parameters:
    ///   - leftSide: The Boolean variable to modify
    ///   - rightSide: The Boolean value to AND with the left side
    ///
    /// ## Example
    /// ```swift
    /// var isValid = true
    /// isValid &= true  // isValid remains true
    /// isValid &= false // isValid is now false
    /// ```
    static public func &= (leftSide: inout Bool, rightSide: Bool) {
        leftSide = leftSide && rightSide
    }

    /// Performs a logical XOR (exclusive OR) operation and assigns the result to the left-hand side variable.
    ///
    /// This operator is equivalent to `leftSide = leftSide != rightSide`. The result is `true`
    /// when the operands have different values, and `false` when they're the same.
    ///
    /// - Parameters:
    ///   - leftSide: The Boolean variable to modify
    ///   - rightSide: The Boolean value to XOR with the left side
    ///
    /// ## Example
    /// ```swift
    /// var toggle = false
    /// toggle ^= true  // toggle is now true
    /// toggle ^= true  // toggle is now false (toggled back)
    /// ```
    static public func ^= (leftSide: inout Bool, rightSide: Bool) {
        leftSide = leftSide != rightSide
    }
}
