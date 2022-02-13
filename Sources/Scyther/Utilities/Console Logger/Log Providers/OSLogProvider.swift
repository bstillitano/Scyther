//
//  OSLogProvider.swift
//
//
//  Created by Brandon Stillitano on 9/2/22.
//

import Foundation
import LogInterface

class OSLogProvider: ConsoleLogProvider {
    // MARK: - SPI
    private let OSActivityStreamForPID: os_activity_stream_for_pid_t
    private let OSActivityStreamResume: os_activity_stream_resume_t
    private let OSActivityStreamCancel: os_activity_stream_cancel_t
    private let OSLogCopyFormattedMessage: os_log_copy_formatted_message_t

    // MARK: - Data
    private let queue: DispatchQueue
    private var stream: os_activity_stream_t!
    private let filterPid = ProcessInfo.processInfo.processIdentifier

    // MARK: - Delegate
    private weak var delegate: ConsoleLogProviderDelegate?

    // MARK: - Lifecycle
    deinit {
        teardown()
    }

    required init?(queue: DispatchQueue, delegate: ConsoleLogProviderDelegate?) {
        // Check environemnt and setup SPI
        guard !AppEnvironment.isTestCase,
            let handle = dlopen("/System/Library/PrivateFrameworks/LoggingSupport.framework/LoggingSupport", RTLD_NOW) else {
            return nil
        }
        OSActivityStreamForPID = unsafeBitCast(dlsym(handle, "os_activity_stream_for_pid"), to: os_activity_stream_for_pid_t.self)
        OSActivityStreamResume = unsafeBitCast(dlsym(handle, "os_activity_stream_resume"), to: os_activity_stream_resume_t.self)
        OSActivityStreamCancel = unsafeBitCast(dlsym(handle, "os_activity_stream_cancel"), to: os_activity_stream_cancel_t.self)
        OSLogCopyFormattedMessage = unsafeBitCast(dlsym(handle, "os_log_copy_formatted_message"), to: os_log_copy_formatted_message_t.self)

        // Setup Data
        self.queue = queue
        self.delegate = delegate
    }

    // MARK: - Setup
    func setup() {
        let activity_stream_flags = os_activity_stream_flag_t(OS_ACTIVITY_STREAM_HISTORICAL | OS_ACTIVITY_STREAM_PROCESS_ONLY)
        stream = OSActivityStreamForPID(filterPid, activity_stream_flags, { entryPointer, error in
            guard error == 0,
                let entry = entryPointer?.pointee else {
                return false
            }
            return self.handleStreamEntry(entry)
        })
        guard stream != nil else { return }
        OSActivityStreamResume(stream)
    }

    func teardown() {
        if let stream = stream {
            OSActivityStreamCancel(stream)
        }
    }
}

// MARK: - Helper Functions
extension OSLogProvider {
    private func handleStreamEntry(_ entry: os_activity_stream_entry_s) -> Bool {
        guard entry.type == OS_ACTIVITY_STREAM_TYPE_LOG_MESSAGE || entry.type == OS_ACTIVITY_STREAM_TYPE_LEGACY_LOG_MESSAGE else { return true }
        var osLogMessage = entry.log_message
        guard let messageTextCopy = OSLogCopyFormattedMessage(&osLogMessage) else { return false }
        let message = String(utf8String: messageTextCopy)
        free(messageTextCopy)
        let date = Date(timeIntervalSince1970: TimeInterval(osLogMessage.tv_gmt.tv_sec))
        let log = ConsoleLog(source: Self.sourceName, message: message ?? "", file: nil, line: nil, timestamp: date)
        self.delegate?.logProvider(self, didRecieve: log)
        return true
    }
}
