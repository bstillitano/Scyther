//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import Foundation

extension Range where Bound == String.Index {
    var nsRange: NSRange {
        return NSRange(location: self.lowerBound.encodedOffset, length: self.upperBound.encodedOffset - self.lowerBound.encodedOffset)
    }
}
