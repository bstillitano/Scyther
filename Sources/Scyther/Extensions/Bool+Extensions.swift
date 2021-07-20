//
//  Bool+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import Foundation

extension Bool {
    var stringValue: String {
        return self ? "true" : "false"
    }

    static public func |= (leftSide: inout Bool, rightSide: Bool) {
        leftSide = leftSide || rightSide
    }

    static public func &= (leftSide: inout Bool, rightSide: Bool) {
        leftSide = leftSide && rightSide
    }

    static public func ^= (leftSide: inout Bool, rightSide: Bool) {
        leftSide = leftSide != rightSide
    }
}
