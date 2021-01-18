//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 18/1/21.
//

import Foundation

extension URL {
    /// Local path pointing to the location fo the console output file that is used by the `ConsoleLoger` class.
    internal static var consoleLogURL: URL? {
        // Get local document directory
        guard let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return nil
        }
        let documentsDirectory = NSURL(fileURLWithPath: documentsPath)
        
        // Construct log path
        guard let logPath = documentsDirectory.appendingPathComponent("console.log") else {
            return nil
        }
        return logPath
    }
}
