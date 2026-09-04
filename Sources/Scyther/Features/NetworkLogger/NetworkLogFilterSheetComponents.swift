//
//  NetworkLogFilterSheetComponents.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI

/// A checklist row shared by ``NetworkLogFilterSheet`` and ``NetworkLogAllFiltersSheet``.
///
/// Renders the option title as a `LabeledContent` label with a tinted checkmark as its content
/// when selected.
struct NetworkLogFilterOptionRow: View {
    /// The text shown for the option.
    let title: String

    /// Whether the option is currently selected.
    let isSelected: Bool

    /// Called when the row is tapped.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent(title) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .foregroundStyle(Color.primary)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The placeholder shown when a log-derived dimension has no values yet.
struct NetworkLogFilterEmptyRow: View {
    /// The lowercased dimension name, e.g. "host".
    let dimensionName: String

    var body: some View {
        Text("No \(dimensionName) values captured yet")
            .fontWeight(.bold)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// The tinted confirmation button that dismisses a filter sheet.
///
/// Uses the system confirm role with its system-provided checkmark label on iOS 26, which
/// renders as prominent tinted glass, and a checkmark in a bordered prominent capsule on
/// earlier releases.
struct NetworkLogFilterConfirmButton: View {
    /// Called when the button is tapped.
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .confirm, action: action)
        } else {
            Button(action: action) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Done")
        }
    }
}

/// A segmented Include / Exclude control shown as the section header of the host checklist.
struct NetworkLogHostModePicker: View {
    /// The current mode.
    let mode: HostFilterMode

    /// Called when a segment is chosen.
    let onChange: (HostFilterMode) -> Void

    var body: some View {
        Picker("Host mode", selection: Binding(get: { mode }, set: onChange)) {
            ForEach(HostFilterMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .textCase(nil)
        .padding(.bottom, 8)
    }
}
