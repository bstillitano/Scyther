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
                Text("No notifications received")
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(viewModel.notifications) { notification in
                    Section(notification.receivedAt) {
                        LabeledContent("Title", value: notification.title ?? "-")
                        LabeledContent("Subtitle", value: notification.subtitle ?? "-")
                        LabeledContent("Body", value: notification.body ?? "-")

                        if let badge = notification.badge {
                            LabeledContent("Badge", value: "\(badge)")
                        }

                        if let category = notification.category {
                            LabeledContent("Category", value: category)
                        }

                        if let contentAvailable = notification.contentAvailable {
                            LabeledContent("Content-Available", value: "\(contentAvailable)")
                        }

                        if let sound = notification.sound {
                            LabeledContent("Sound", value: sound)
                        }

                        NavigationLink("View User-Additional Data") {
                            TextReaderView(
                                text: notification.additionalDataJson,
                                title: "Additional Push Data"
                            )
                        }
                        .foregroundStyle(.tint)

                        NavigationLink("View Raw Payload") {
                            TextReaderView(
                                text: notification.rawPayloadJson,
                                title: "Raw Push Payload"
                            )
                        }
                        .foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle("Notification Logger")
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

/// View model managing the notification logger display.
///
/// Loads notifications from `NotificationTester` and listens for new
/// notifications via `NotificationCenter`.
class NotificationLoggerViewModel: ViewModel {
    @Published var notifications: [NotificationLogItem] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadNotifications()
    }

    @MainActor
    func refresh() async {
        await loadNotifications()
    }

    @MainActor
    private func loadNotifications() async {
        notifications = NotificationTester.instance.notifications
            .sorted { ($0.receivedAt ?? Date()) > ($1.receivedAt ?? Date()) }
            .map { notification in
                NotificationLogItem(
                    receivedAt: notification.receivedAt?.formatted(format: "dd MMM yyyy h:mm:ss a") ?? "Unknown",
                    title: notification.aps.alert.title,
                    subtitle: notification.aps.alert.subtitle,
                    body: notification.aps.alert.body,
                    badge: notification.aps.badge,
                    category: notification.aps.category,
                    contentAvailable: notification.aps.contentAvailable,
                    sound: notification.aps.sound,
                    additionalDataJson: notification.additionalData.jsonString ?? "{}",
                    rawPayloadJson: notification.rawPayload.jsonString ?? "{}"
                )
            }
    }
}

#Preview {
    NavigationStack {
        NotificationLoggerView()
    }
}
