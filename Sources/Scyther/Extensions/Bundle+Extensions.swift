//
//  Bundle+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

import Foundation

extension Bundle {
    public var versionNumber: String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    public var buildNumber: String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    public var buildDate: Date {
        guard let infoPath = self.path(forResource: "Info", ofType: "plist") else {
            return Date()
        }
        guard let infoAttributes = try? FileManager.default.attributesOfItem(atPath: infoPath) else {
            return Date()
        }
        return infoAttributes[.modificationDate] as? Date ?? Date()
    }
}

/// Cocoapods Specific Extensions
#if !SWIFT_PACKAGE
extension Bundle {
    static var module: Bundle {
        Bundle(identifier: "org.cocoapods.Scyther")!
    }
}
#endif
