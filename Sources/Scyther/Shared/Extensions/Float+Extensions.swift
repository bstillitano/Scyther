//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 7/4/2024.
//

import Foundation

extension Float {
    /// Returns a ``String`` representation of this value, with no decimals. 
    var clean: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
    
    /// Returns the integer part of the float as a string, without rounding.
    var withoutDecimals: String {
        return String(Int(self))
    }
}
