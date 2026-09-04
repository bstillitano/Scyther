//
//  NetworkLogExportViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import Foundation

/// View model backing ``NetworkLogExportSheet``.
///
/// On first appearance it builds the zip archive for the supplied requests off the main actor,
/// publishing ``state`` transitions so the sheet can show progress, the finished archive, or an
/// error. Toggling ``redactSensitiveValues`` through ``setRedaction(_:)`` rebuilds the archive.
/// ``cleanup()`` deletes the archive when the sheet closes.
///
/// ## Usage
///
/// ```swift
/// let viewModel = NetworkLogExportViewModel(requests: listViewModel.requests)
/// ```
final class NetworkLogExportViewModel: ViewModel {
    /// The stages of an export.
    enum State: Equatable, Sendable {
        /// The archive is being written.
        case preparing
        /// The archive is ready at the given URL.
        case ready(URL)
        /// The export failed with a user-facing message.
        case failed(String)
    }

    /// The requests being exported.
    let requests: [HTTPRequest]

    /// The current stage of the export.
    @Published private(set) var state: State = .preparing

    /// Whether the archive is passed through ``NetworkLogRedactor``. Defaults to on.
    @Published private(set) var redactSensitiveValues: Bool = true

    /// Whether a replacement archive is being built after a setting change.
    ///
    /// While true, ``state`` still holds the previous archive so the sheet can keep its rows in
    /// place and show an inline spinner rather than tearing the section down.
    @Published private(set) var isRebuilding: Bool = false

    /// Produces the archive for the requests and redaction flag. Injected so tests can avoid real zipping.
    private let exporter: @Sendable ([HTTPRequest], Bool) throws -> URL

    /// The shortest time a rebuild is allowed to take, so the inline spinner is seen rather than flickering.
    static let defaultMinimumRebuildDuration: Duration = .milliseconds(750)

    /// The minimum wall-clock time for a rebuild triggered by ``setRedaction(_:)``.
    private let minimumRebuildDuration: Duration

    /// Creates an export view model.
    ///
    /// - Parameters:
    ///   - requests: The requests to export.
    ///   - minimumRebuildDuration: Floor on how long a rebuild appears to take. Defaults to
    ///     ``defaultMinimumRebuildDuration``; pass `.zero` in tests.
    ///   - exporter: Builds the archive. Defaults to ``NetworkLogExporter/export(_:in:now:redact:)``.
    init(
        requests: [HTTPRequest],
        minimumRebuildDuration: Duration = defaultMinimumRebuildDuration,
        exporter: @escaping @Sendable ([HTTPRequest], Bool) throws -> URL = { requests, redact in
            try NetworkLogExporter.export(requests, redact: redact)
        }
    ) {
        self.requests = requests
        self.minimumRebuildDuration = minimumRebuildDuration
        self.exporter = exporter
        super.init()
    }

    /// The number of requests in the archive.
    var requestCount: Int { requests.count }

    /// The finished archive, once ``state`` is ``State/ready(_:)``.
    var archiveURL: URL? {
        if case .ready(let url) = state { return url }
        return nil
    }

    /// The finished archive's filename, for display.
    var archiveFilename: String? { archiveURL?.lastPathComponent }

    /// Builds the archive off the main actor and publishes the outcome.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await build()
    }

    /// Changes the redaction setting and rebuilds the archive.
    ///
    /// The setting and ``isRebuilding`` flip synchronously so a bound `Toggle` never bounces. The
    /// previous archive stays in ``state`` until the replacement is ready, after which the old
    /// file is deleted. The rebuild is padded to at least the minimum duration so the spinner is
    /// visible rather than a flicker.
    ///
    /// - Parameter enabled: Whether to redact.
    /// - Returns: The rebuild task, or `nil` when the value did not change. Await it in tests.
    @discardableResult
    func setRedaction(_ enabled: Bool) -> Task<Void, Never>? {
        guard enabled != redactSensitiveValues else { return nil }
        redactSensitiveValues = enabled
        isRebuilding = true
        let previous = archiveURL
        let minimum = minimumRebuildDuration
        return Task { @MainActor in
            let started = ContinuousClock.now
            await build()
            let remaining = minimum - (ContinuousClock.now - started)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            isRebuilding = false
            if let previous, previous != archiveURL {
                try? FileManager.default.removeItem(at: previous)
            }
        }
    }

    private func build() async {
        let requests = self.requests
        let redact = self.redactSensitiveValues
        let exporter = self.exporter
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try exporter(requests, redact)
            }.value
            state = .ready(url)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Deletes the archive file, if one was produced.
    func cleanup() {
        guard let archiveURL else { return }
        try? FileManager.default.removeItem(at: archiveURL)
    }
}
