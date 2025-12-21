//
//  CrashLogEntry.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/12/2024.
//

#if !os(macOS)
import Foundation

/// A model representing a captured crash/exception.
public struct CrashLogEntry: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this crash entry.
    public let id: UUID

    /// Timestamp when the crash occurred.
    public let timestamp: Date

    /// Exception name (e.g., "NSInvalidArgumentException").
    public let name: String

    /// Exception reason/message.
    public let reason: String?

    /// Stack trace symbols at the time of crash.
    public let stackTrace: [String]

    /// App version when crash occurred.
    public let appVersion: String

    /// Build number when crash occurred.
    public let buildNumber: String

    /// OS version when crash occurred.
    public let osVersion: String

    /// Device model when crash occurred.
    public let deviceModel: String

    /// Creates a new crash log entry.
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        name: String,
        reason: String?,
        stackTrace: [String],
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.reason = reason
        self.stackTrace = stackTrace
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }

    /// Formatted timestamp for display.
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    /// Short summary for list display.
    public var summary: String {
        reason ?? name
    }

    /// Full crash report as text for sharing/copying.
    public var fullReport: String {
        var report = """
        Crash Report
        ============

        Date: \(formattedTimestamp)
        Exception: \(name)
        Reason: \(reason ?? "Unknown")

        Device: \(deviceModel)
        OS Version: \(osVersion)
        App Version: \(appVersion) (\(buildNumber))

        Stack Trace:
        """

        for (index, symbol) in stackTrace.enumerated() {
            report += "\n\(index): \(symbol)"
        }

        return report
    }
}
#endif
