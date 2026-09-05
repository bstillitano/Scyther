//
//  ConfirmButton.swift
//  Scyther
//

import SwiftUI

/// The tinted confirmation button that commits a sheet or an editor.
///
/// Uses the system confirm role with its system-provided checkmark label on iOS 26, which renders
/// as prominent tinted glass, and a checkmark in a bordered prominent capsule on earlier releases.
/// Scyther uses this everywhere a screen is committed rather than a worded button, so the confirm
/// affordance looks the same across the toolkit.
struct ConfirmButton: View {
    /// Called when the button is tapped.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: Called when the button is tapped.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .confirm, action: action)
        } else {
            Button(action: action) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityLabel(localized("Done"))
        }
    }
}
