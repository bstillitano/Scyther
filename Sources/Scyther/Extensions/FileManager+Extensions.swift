//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import Foundation

internal extension FileManager {
    /// Determines whether or not a directory exists at the given URL
    /// - Parameter url: URL to check for directory existence
    /// - Returns: A `Bool` value representing whether or not a directory exists at the given URL
    func directoryExists(atUrl url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
