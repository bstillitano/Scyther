//
//  CloseButton.swift
//  Scyther
//

import SwiftUI

/// The button that closes a screen without deciding anything.
///
/// The counterpart to ``ConfirmButton``, and deliberately not it: a tick says the developer is
/// committing what is in front of them, and a screen with nothing left on it has nothing to
/// commit. Uses the system close role and its system-provided label on iOS 26, which renders as
/// the circular glass cross, and a cross in a bordered capsule on earlier releases.
struct CloseButton: View {
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
            Button(role: .close, action: action)
        } else {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel(localized("Close"))
        }
    }
}
