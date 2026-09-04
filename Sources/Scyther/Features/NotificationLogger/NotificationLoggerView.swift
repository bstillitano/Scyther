//
//  NotificationLoggerView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A view displaying a log of all push notifications received by the application.
///
/// Shows detailed information about each notification including:
/// - Title, subtitle, and body text
/// - Badge count and category
/// - Sound and content-available flags
/// - Custom additional data
/// - Complete raw payload
///
/// The view automatically updates when new notifications are logged.
struct NotificationLoggerView: View {
    @StateObject private var viewModel = NotificationLoggerViewModel()

    var body: some View {
        List {
            if viewModel.notifications.isEmpty {
                Text(localized("No notifications received"))
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.notifications) { notification in
                    Section(notification.receivedAt) {
                        LabeledContent(localized("Title"), value: notification.title ?? "-")
                        LabeledContent(localized("Subtitle"), value: notification.subtitle ?? "-")
                        LabeledContent(localized("Body"), value: notification.body ?? "-")

                        if let badge = notification.badge {
                            LabeledContent(localized("Badge"), value: "\(badge)")
                        }

                        if let category = notification.category {
                            LabeledContent(localized("Category"), value: category)
                        }

                        if let contentAvailable = notification.contentAvailable {
                            LabeledContent("Content-Available", value: "\(contentAvailable)") // scyther:unlocalised APNS payload key name
                        }

                        if let sound = notification.sound {
                            LabeledContent(localized("Sound"), value: sound)
                        }

                        NavigationLink(localized("View User-Additional Data")) {
                            TextReaderView(
                                text: notification.additionalDataJson,
                                title: localized("Additional Push Data")
                            )
                        }
                        .foregroundStyle(.tint)

                        NavigationLink(localized("View Raw Payload")) {
                            TextReaderView(
                                text: notification.rawPayloadJson,
                                title: localized("Raw Push Payload")
                            )
                        }
                        .foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle(localized("Notification Logger"))
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NotificationLoggerLoggedData)) { _ in
            Task { await viewModel.refresh() }
        }
    }
}

/// A model representing a logged push notification for display.
struct NotificationLogItem: Identifiable {
    let id = UUID()

    /// The formatted timestamp when the notification was received.
    let receivedAt: String

    /// The notification title.
    let title: String?

    /// The notification subtitle.
    let subtitle: String?

    /// The notification body text.
    let body: String?

    /// The badge count set by the notification.
    let badge: Int?

    /// The notification category identifier.
    let category: String?

    /// The content-available flag value.
    let contentAvailable: Int?

    /// The sound file name or "default".
    let sound: String?

    /// JSON string of custom additional data.
    let additionalDataJson: String

    /// JSON string of the complete raw payload.
    let rawPayloadJson: String
}

#Preview {
    NavigationStack {
        NotificationLoggerView()
    }
}
