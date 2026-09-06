//
//  NetworkConditioningView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 5/9/2026.
//

import SwiftUI

/// Degrades every request Scyther intercepts, reached from **Networking → Network Conditioning**.
///
/// The equivalent of Network Link Conditioner, without the developer having to install a profile
/// or reach for a Mac: a master switch, a picker of the links people actually name, and the three
/// numbers underneath it for when none of them is quite right.
///
/// A request override with its own condition still wins — see ``NetworkConditioningStore`` — so
/// this is the floor for the whole app rather than the last word on any one endpoint.
///
/// ## Usage
/// ```swift
/// NavigationStack {
///     NetworkConditioningView()
/// }
/// ```
struct NetworkConditioningView: View {
    /// The screen's view model, mirroring ``NetworkConditioningStore``.
    @StateObject private var viewModel: NetworkConditioningViewModel

    /// Creates the screen.
    ///
    /// - Parameter store: The store to show. Defaults to the shared store; a preview or a test
    ///   harness passes a throwaway one.
    init(store: NetworkConditioningStore = .shared) {
        _viewModel = StateObject(wrappedValue: NetworkConditioningViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Toggle(localized("Enable Network Conditioning"), isOn: $viewModel.isEnabled)
            } footer: {
                Text(localized("Applies to every request Scyther intercepts. An override with its own condition takes precedence."))
            }

            Section {
                Picker(localized("Preset"), selection: $viewModel.preset) {
                    ForEach(viewModel.offeredPresets) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
            } footer: {
                Text(localized("Custom is what the three numbers below read as when they match no named link."))
            }

            Section {
                LabeledContent(localized("Latency (seconds)")) {
                    TextField(localized("Latency (seconds)"), value: $viewModel.latency, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                LabeledContent(localized("Bandwidth (KB/s)")) {
                    TextField(localized("Bandwidth (KB/s)"), value: $viewModel.bandwidthKBps, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
            } footer: {
                Text(localized("0 means unthrottled."))
            }

            Section {
                LabeledContent(
                    localized("Failure rate"),
                    value: viewModel.failureRate.formatted(.percent.precision(.fractionLength(0)))
                )
                Slider(value: $viewModel.failureRate, in: 0...1, step: 0.05)
                    .accessibilityLabel(localized("Failure rate"))
            }
        }
        .navigationTitle(localized("Network Conditioning"))
    }
}
