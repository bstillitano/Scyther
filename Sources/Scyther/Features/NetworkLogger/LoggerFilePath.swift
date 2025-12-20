//
//  LoggerFilePath.swift
//  
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

struct LoggerFilePath {
    /// Safely accessed documents directory, will return an empty string if no directory is available
    static var Documents: NSString {
        guard let documentPath = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory,
                                                                     FileManager.SearchPathDomainMask.allDomainsMask,
                                                                     true).first as NSString? else {
            return ""
        }
        return documentPath
    }

    /// Full file path for the locally stored networking session logs.
    static let SessionLog = LoggerFilePath.Documents.appendingPathComponent("SessionLog.log");
}
