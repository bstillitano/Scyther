//
//  File.swift
//
//
//  Created by Brandon Stillitano on 9/2/22.
//

import UIKit

public class ConsoleLogger {
    // MARK: - Singleton
    /// An initialised, shared instance of the `ConfigurationSwitcher` class.
    static let instance = ConsoleLogger()

    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() {
        guard let logFileURL = Self.initialiseSessionLog() else {
            assertionFailure("Unable to create the log file")
            return
        }
        self.logFileLocation = logFileURL

        // Setup FileHandle
        do {
            logFileHandle = try FileHandle(forWritingTo: logFileURL)
        } catch {
            assertionFailure("Failed to create log file handle, Error: \(error)")
        }
        logFileHandle?.seekToEndOfFile()

        // Perform Initial Cleanup
        guard let offsetInFile = logFileHandle?.offsetInFile else { return }
        logSize = Double(offsetInFile)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.cleanup()
        }
    }

    // MARK: - Data
    private var logFileHandle: FileHandle?
    internal var logFileLocation: URL?
    private let providerQueue = DispatchQueue(label: "io.stillitano.ScytherInternal.consolelogger", qos: .utility, autoreleaseFrequency: .workItem, target: .global(qos: .utility))
    private let processingQueue = DispatchQueue(label: "io.stillitano.ScytherInternal.consolelogger.processing", qos: .utility, autoreleaseFrequency: .workItem, target: .global(qos: .utility))
    internal static var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(identifier: "GMT") ?? .autoupdatingCurrent
        return formatter
    }()

    // MARK: - Configuration
    private var logSize: Double = 0
    private let maximumLogSize: Double = 2 * 1_000_000 // 2mb
    private let trimSize: Double = 100 * 1000 // 100kb
    private let minmumRequiredDiskSpace: Double = 500 * 1_000_000 // 500mb
    public var providerTypes: [ConsoleLogProvider.Type] = []
    internal var providers: [ConsoleLogProvider] = []

    // MARK: - Setup
    internal func start() {
        if providerTypes.isEmpty { providerTypes = ProtocolDefaultsLogProvider.allProviders }
        providers = providerTypes.compactMap({ $0.init(queue: providerQueue, delegate: self) })
        providers.forEach { $0.setup() }
        startSession()
    }
}

// MARK: - Helper Functions
extension ConsoleLogger {
    // MARK: - Static Data
    private static let diagnosticsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics", isDirectory: true)
    private static let logDirectory = ConsoleLogger.diagnosticsDirectory.appendingPathComponent("logs", isDirectory: true)
    private static let numberOfDaysToStoreLogs = 7

    /// Creates a log file for the current session and returns the URL to that file.
    /// - Returns: A `URL` pointing to the created log file
    internal class func initialiseSessionLog() -> URL? {
        // Setup Data
        let sessionIdentifier = UUID().uuidString
        let logFile = Self.logDirectory.appendingPathComponent("session_\(sessionIdentifier).log")

        // Create Directory & Encrypt File
        if !FileManager.default.directoryExists(atUrl: Self.logDirectory) {
            try? FileManager.default.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        guard FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: nil) else {
            return nil
        }
        try? (logFile as NSURL).setResourceValue(URLFileProtection.completeUnlessOpen, forKey: .fileProtectionKey)

        return logFile
    }

    @objc
    func cleanup() {
        // Get required data
        guard let directoryContents = try? FileManager.default.contentsOfDirectory(at: Self.logDirectory, includingPropertiesForKeys: nil),
            let maxiumLogCreationDate = Calendar.current.date(byAdding: .day, value: Self.numberOfDaysToStoreLogs * -1, to: Date()) else {
            return
        }

        // Iterate directory and delete stale logs
        directoryContents.forEach { url in
            let fileAtributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileCreationDate = fileAtributes?[FileAttributeKey.creationDate] as? Date,
                maxiumLogCreationDate > fileCreationDate else {
                return
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - DiagnosticsLogProviderDelegate
extension ConsoleLogger: ConsoleLogProviderDelegate {
    public func logProvider(_ provider: ConsoleLogProvider?, didRecieve log: ConsoleLog) {
        self.log(log)
    }
}

// MARK: - Logging
internal extension ConsoleLogger {
    /// Returns the avialable disk space of the running device, in Bytes.
    private var availableDiskSace: Double {
        let values = try? logFileLocation?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Triggers the start of the logging session and starts capturing messages from the `providers` object
    private func startSession() {
        processingQueue.async { [weak self] in
            let date = Self.formatter.string(from: Date())
            let appVersion = UIApplication.shared.appVersion ?? "N/A"
            let system = ProcessInfo.processInfo.operatingSystemVersionString
            let locale = Locale.preferredLanguages.first ?? Locale.current.identifier
            let message = date + "\n" + "System: \(system)\nLocale: \(locale)\nApp Version: \(appVersion)\n\n"
            self?.log("\(self?.logSize ?? 0 > 0 ? "\n\n---------\n\n" : "")\(message)")
        }
    }

    /// Deletes the log file for the current session
    func clearSessionLogs() {
        guard let logFile = logFileLocation, FileManager.default.fileExists(atPath: logFile.path) else { return }
        try? FileManager.default.removeItem(atPath: logFile.path)
    }

    private func log(message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        guard logFileHandle != nil else {
            return
        }
        processingQueue.async { [weak self] in
            let date = Self.formatter.string(from: Date())
            let file = file.split(separator: "/").last.map(String.init) ?? file
            let output = String(format: "%@ | %@:L%@ | %@\n", date, file, String(line), message)
            self?.log(output)
        }
    }

    func log(_ message: ConsoleLog) {
        guard logFileHandle != nil else {
            return
        }
        providerQueue.async { [weak self] in
            self?.log(message.formattedMessage)
        }
    }

    private func log(_ output: String) {
        // Ensure that we have the required resources and data to log the `output` value
        guard let data = output.data(using: .utf8),
            let fileHandle = logFileHandle,
            availableDiskSace > minmumRequiredDiskSpace else {
            return
        }

        // Write `output` to file
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        logSize += Double(data.count)
        providerQueue.async { [weak self] in
            self?.trimLinesIfNecessary()
        }
    }

    private func trimLinesIfNecessary() {
        // Confirm we have a valid log file
        guard let logFile = logFileLocation,
            logSize > maximumLogSize else {
            return
        }

        // Create file data
        var logFileData: Data?
        do {
            logFileData = try Data(contentsOf: logFile, options: .mappedIfSafe)
        } catch {
            return
        }

        // Ensure data is valid amd ready for processing
        guard var data = logFileData,
            data.isEmpty == false,
            let newLine = "\n".data(using: .utf8) else {
            return
        }

        // Get log size down to a managable size
        var position: Int = 0
        while logSize - Double(position) > (maximumLogSize - trimSize) {
            guard let range = data.firstRange(of: newLine, in: position ..< data.count) else { break }
            position = range.startIndex.advanced(by: 1)
        }
        logSize = logSize - Double(position)
        data.removeSubrange(0 ..< position)

        // Write data to log
        guard (try? data.write(to: logFile, options: .atomic)) != nil else {
            return
        }
    }
}
