//
//  Date+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

import Foundation

extension Date {
    public func formatted(format: String = "dd/MM/yyyy hh:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}
