//
//  ConsoleLogger.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

#if !os(macOS)
import Foundation

public extension NSNotification.Name {
    static let ConsoleLoggerDidLog = Notification.Name("ConsoleLoggerDidLog")
}

public struct ConsoleLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let source: LogSource

    public enum LogSource: String {
        case stdout = "stdout"
        case stderr = "stderr"
    }

    public var formattedTimestamp: String {
        timestamp.formatted(date: .omitted, time: .standard)
    }
}

public final class ConsoleLogger {
    // MARK: - Singleton
    public static let instance = ConsoleLogger()

    // MARK: - Static Data
    private static let MaxLogEntries = 5000

    // MARK: - Data
    private var logs: [ConsoleLogEntry] = []
    private let logsQueue = DispatchQueue(label: "com.scyther.consolelogger", attributes: .concurrent)

    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1

    private(set) var isCapturing = false

    // MARK: - Init
    private init() {}

    // MARK: - Public API
    public var allLogs: [ConsoleLogEntry] {
        logsQueue.sync { logs }
    }

    public func start() {
        guard !isCapturing else { return }
        isCapturing = true

        // Capture stdout
        captureStdout()

        // Capture stderr
        captureStderr()
    }

    public func stop() {
        guard isCapturing else { return }
        isCapturing = false

        // Restore stdout
        if originalStdout != -1 {
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            originalStdout = -1
        }
        stdoutPipe = nil

        // Restore stderr
        if originalStderr != -1 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }
        stderrPipe = nil
    }

    public func clear() {
        logsQueue.async(flags: .barrier) {
            self.logs.removeAll()
        }
        NotificationCenter.default.post(name: .ConsoleLoggerDidLog, object: nil)
    }

    // MARK: - Capture Implementation
    private func captureStdout() {
        stdoutPipe = Pipe()
        guard let pipe = stdoutPipe else { return }

        // Save original stdout
        originalStdout = dup(STDOUT_FILENO)

        // Redirect stdout to pipe
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        // Also write to original stdout so Xcode console still works
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Write to original stdout
            if let self = self, self.originalStdout != -1 {
                write(self.originalStdout, (data as NSData).bytes, data.count)
            }

            // Parse and store log
            if let message = String(data: data, encoding: .utf8) {
                self?.addLog(message: message, source: .stdout)
            }
        }
    }

    private func captureStderr() {
        stderrPipe = Pipe()
        guard let pipe = stderrPipe else { return }

        // Save original stderr
        originalStderr = dup(STDERR_FILENO)

        // Redirect stderr to pipe
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        // Also write to original stderr so Xcode console still works
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Write to original stderr
            if let self = self, self.originalStderr != -1 {
                write(self.originalStderr, (data as NSData).bytes, data.count)
            }

            // Parse and store log
            if let message = String(data: data, encoding: .utf8) {
                self?.addLog(message: message, source: .stderr)
            }
        }
    }

    private func addLog(message: String, source: ConsoleLogEntry.LogSource) {
        // Split by newlines and create separate entries for each line
        let lines = message.components(separatedBy: .newlines).filter { !$0.isEmpty }

        logsQueue.async(flags: .barrier) {
            for line in lines {
                let entry = ConsoleLogEntry(
                    timestamp: Date(),
                    message: line,
                    source: source
                )
                self.logs.append(entry)
            }

            // Trim old logs if over limit
            if self.logs.count > Self.MaxLogEntries {
                self.logs.removeFirst(self.logs.count - Self.MaxLogEntries)
            }
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .ConsoleLoggerDidLog, object: nil)
        }
    }
}
#endif
