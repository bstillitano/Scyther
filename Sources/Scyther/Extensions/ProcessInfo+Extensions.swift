//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 10/2/22.
//

import Foundation

public extension ProcessInfo {
    /// Returns a `Bool` value representing whether or not the running process is being run as part of an XCTestCase or XCUITestCase
    var isRunningInTestEnvironment: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
