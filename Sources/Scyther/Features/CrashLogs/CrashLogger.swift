//
//  CrashLogger.swift
//  Scyther
//
//  Created by Brandon Stillitano on 22/12/2024.
//

#if !os(macOS)
import Foundation
import UIKit

/// A singleton that captures uncaught exceptions and stores them for viewing.
///
/// CrashLogger uses `NSSetUncaughtExceptionHandler` to intercept crashes.
/// It chains to any previously installed handler (e.g., Firebase Crashlytics)
/// so multiple crash reporters can coexist.
///
/// - Important: Call `Scyther.start()` AFTER initializing other crash reporters
///   (like Firebase) to ensure proper handler chaining.
public final class CrashLogger: @unchecked Sendable {
    /// Shared instance.
    public static let instance = CrashLogger()

    /// UserDefaults key for storing crash logs.
    private static let storageKey = "Scyther_CrashLogs"

    /// Maximum number of crashes to store.
    private static let maxCrashes = 50

    /// Previously installed exception handler (e.g., Crashlytics).
    /// We forward crashes to this handler after logging.
    nonisolated(unsafe) private static var previousHandler: (@convention(c) (NSException) -> Void)?

    /// Cached device info captured at startup (safe to access from exception handler).
    nonisolated(unsafe) private static var cachedOSVersion: String = "Unknown"
    nonisolated(unsafe) private static var cachedDeviceModel: String = "Unknown"
    nonisolated(unsafe) private static var cachedAppVersion: String = "Unknown"
    nonisolated(unsafe) private static var cachedBuildNumber: String = "Unknown"

    /// Whether the crash handler has been installed.
    private var isStarted = false

    /// Notification posted when a new crash is recorded.
    public static let didRecordCrashNotification = Notification.Name("CrashLoggerDidRecordCrash")

    private init() {}

    /// All stored crash logs, newest first.
    public var allCrashes: [CrashLogEntry] {
        load()
    }

    /// Number of stored crashes.
    public var crashCount: Int {
        allCrashes.count
    }

    /// Starts the crash logger by installing the exception handler.
    ///
    /// This should be called during app initialization, after any other
    /// crash reporters (like Firebase Crashlytics) have been configured.
    @MainActor
    public func start() {
        guard !isStarted else { return }
        isStarted = true

        // Cache device info now (on main thread) so it's available during crashes
        CrashLogger.cachedOSVersion = UIDevice.current.systemVersion
        CrashLogger.cachedDeviceModel = UIDevice.current.model
        CrashLogger.cachedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        CrashLogger.cachedBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        // Save any existing handler so we can chain to it
        CrashLogger.previousHandler = NSGetUncaughtExceptionHandler()

        // Install our handler
        NSSetUncaughtExceptionHandler { exception in
            // Record the crash
            CrashLogger.recordCrash(exception)

            // Forward to previous handler (e.g., Crashlytics)
            CrashLogger.previousHandler?(exception)
        }
    }

    /// Records a crash from an exception.
    /// Called from the exception handler - keep this fast and safe.
    private static func recordCrash(_ exception: NSException) {
        let entry = CrashLogEntry(
            name: exception.name.rawValue,
            reason: exception.reason,
            stackTrace: exception.callStackSymbols,
            appVersion: cachedAppVersion,
            buildNumber: cachedBuildNumber,
            osVersion: cachedOSVersion,
            deviceModel: cachedDeviceModel
        )

        // Load existing crashes
        var crashes = CrashLogger.instance.load()

        // Add new crash at the beginning
        crashes.insert(entry, at: 0)

        // Trim to max size
        if crashes.count > maxCrashes {
            crashes = Array(crashes.prefix(maxCrashes))
        }

        // Save immediately - we're about to crash
        CrashLogger.instance.save(crashes)
    }

    /// Clears all stored crash logs.
    public func clear() {
        UserDefaults.standard.removeObject(forKey: CrashLogger.storageKey)
        NotificationCenter.default.post(name: CrashLogger.didRecordCrashNotification, object: nil)
    }

    /// Loads crash logs from UserDefaults.
    private func load() -> [CrashLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: CrashLogger.storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([CrashLogEntry].self, from: data)
        } catch {
            return []
        }
    }

    /// Saves crash logs to UserDefaults.
    private func save(_ crashes: [CrashLogEntry]) {
        do {
            let data = try JSONEncoder().encode(crashes)
            UserDefaults.standard.set(data, forKey: CrashLogger.storageKey)
            UserDefaults.standard.synchronize() // Force immediate write - we're crashing
        } catch {
            // Can't do much if encoding fails during a crash
        }
    }

    // MARK: - Testing Support

    /// Triggers a test crash. Only available in debug builds.
    ///
    /// - Warning: This will crash the app!
    #if DEBUG
    public func triggerTestCrash() {
        let exception = NSException(
            name: NSExceptionName("ScytherTestCrash"),
            reason: "This is a test crash triggered from Scyther",
            userInfo: nil
        )
        exception.raise()
    }
    #endif
}
#endif
