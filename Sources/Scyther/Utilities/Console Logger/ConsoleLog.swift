//
//  File.swift
//
//
//  Created by Brandon Stillitano on 9/2/22.
//

import Foundation

public struct ConsoleLog {
    var source: String
    var message: String
    var file: String?
    var line: String?
    var timestamp: Date?
}

// MARK: Formatting
public extension ConsoleLog {
    var formattedMessage: String {
        let date = ConsoleLogger.formatter.string(from: timestamp ?? Date())
        return String(format: "%@ | %@\n", date, message)
    }
}
