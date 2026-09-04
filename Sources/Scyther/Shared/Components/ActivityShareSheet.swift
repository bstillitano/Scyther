//
//  ActivityShareSheet.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI
import UIKit

/// The system share sheet, for the one case `ShareLink` cannot cover: opening it from an alert action.
///
/// Present it with `.sheet(isPresented:)`. Prefer `ShareLink` wherever the share is triggered
/// directly by a tap on a view.
struct ActivityShareSheet: UIViewControllerRepresentable {
    /// The items to share, typically file URLs.
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
