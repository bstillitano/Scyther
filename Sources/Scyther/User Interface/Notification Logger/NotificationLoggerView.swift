//
//  NotificationLoggerView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct NotificationLoggerView: View {
    @StateObject private var viewModel = NotificationLoggerSwiftUIViewModel()

    var body: some View {
        List {
            if viewModel.notifications.isEmpty {
                Text("No notifications received")
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
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

                        NavigationLink("View Raw Payload") {
                            TextReaderView(
                                text: notification.rawPayloadJson,
                                title: "Raw Push Payload"
                            )
                        }
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

struct NotificationLogItem: Identifiable {
    let id = UUID()
    let receivedAt: String
    let title: String?
    let subtitle: String?
    let body: String?
    let badge: Int?
    let category: String?
    let contentAvailable: Int?
    let sound: String?
    let additionalDataJson: String
    let rawPayloadJson: String
}

class NotificationLoggerSwiftUIViewModel: ViewModel {
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
