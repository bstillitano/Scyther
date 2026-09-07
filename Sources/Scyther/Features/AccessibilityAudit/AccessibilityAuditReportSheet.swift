//
//  AccessibilityAuditReportSheet.swift
//  Scyther
//
//  Created by Brandon Stillitano on 6/9/2026.
//

#if !os(macOS)
import SwiftUI

/// ``AccessibilityAuditView`` as it appears when the live overlay's count pill opens it over the
/// running app.
///
/// The report itself is written to be pushed inside Scyther's menu, where the menu supplies the
/// navigation stack and the way back. Presented over the app there is neither, so this wrapper
/// supplies both — the same shape ``HeldRequestsView`` uses for the same reason. Keeping it here
/// rather than putting a close button inside ``AccessibilityAuditView`` means the pushed copy in
/// the menu does not grow a second, redundant way out beside the navigation bar's own back button.
///
/// The sheet is deliberately dismissible by swipe as well as by the close button: nothing is
/// waiting on it — unlike a held request, which has to be decided — and a developer who opened it
/// by accident should be able to flick it away and carry on using the app.
struct AccessibilityAuditReportSheet: View {
    /// Closes the presentation this view was put up in.
    ///
    /// The presenter deliberately has no dismissal path of its own: this is an ordinary sheet, so
    /// the environment's own dismissal is the whole mechanism, and
    /// `AccessibilityAuditReportPresenter` simply notices afterwards that the screen has gone.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AccessibilityAuditView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton {
                            dismiss()
                        }
                    }
                }
        }
    }
}

#Preview {
    AccessibilityAuditReportSheet()
}
#endif
