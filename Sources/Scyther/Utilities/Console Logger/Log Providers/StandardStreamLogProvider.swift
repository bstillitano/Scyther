//
//  StandardStreamLogProvider.swift
//
//
//  Created by Brandon Stillitano on 9/2/22.
//

import Foundation

internal class StandardStreamLogProvider: ConsoleLogProvider {
    // MARK: - Data
    internal let inputPipe = Pipe()
    internal let outputPipe = Pipe()
    private let queue: DispatchQueue

    // MARK: - Delegate
    private weak var delegate: ConsoleLogProviderDelegate?

    // MARK: - Lifecycle
    required init?(queue: DispatchQueue, delegate: ConsoleLogProviderDelegate?) {
        // Don't run in a test enviroment
        guard !ProcessInfo.processInfo.isRunningInTestEnvironment else { return nil }

        self.queue = queue
        self.delegate = delegate
    }

    // MARK: - Setup
    func setup() {
        inputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async {
                self?.process(data)
            }
        }
        dup2(STDOUT_FILENO, outputPipe.fileHandleForWriting.fileDescriptor)
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    }

    func teardown() {
        // Intentionally unimplemented
    }
}

// MARK: - Helper Functions
extension StandardStreamLogProvider {
    // MARK: - Private
    private func process(_ data: Data) {
        outputPipe.fileHandleForWriting.write(data)
        guard let string = String(data: data, encoding: .utf8) else {
            return assertionFailure("Attempted to log non utf8 data")
        }
        string.enumerateLines { [weak self] (line, _) in
            let log = ConsoleLog(source: Self.sourceName, message: line, file: nil, line: nil, timestamp: Date())
            self?.delegate?.logProvider(self, didRecieve: log)
        }
    }
}
