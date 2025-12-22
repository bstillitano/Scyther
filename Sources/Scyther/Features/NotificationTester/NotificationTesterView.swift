//
//  NotificationTesterView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import UserNotifications

/// A SwiftUI view for testing and managing local push notifications.
///
/// This view provides a comprehensive interface for:
/// - Checking and requesting notification permissions
/// - Configuring and sending test notifications
/// - Managing app badge count
/// - Viewing and canceling scheduled notifications
///
/// The view automatically refreshes the scheduled notifications list every second
/// to keep the UI in sync with the notification center.
struct NotificationTesterView: View {
    @StateObject private var viewModel = NotificationTesterViewModel()

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Permission Status")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(viewModel.permissionStatusText)
                        .foregroundStyle(viewModel.permissionStatusColor)
                }

                if viewModel.authorizationStatus == .notDetermined {
                    Button("Request Permission") {
                        viewModel.requestPermission()
                    }
                } else if viewModel.authorizationStatus == .denied {
                    Button("Open Settings") {
                        viewModel.openSettings()
                    }
                }
            } header: {
                Text("Push Notifications")
            } footer: {
                if viewModel.authorizationStatus == .denied {
                    Text("Permission was denied. You can enable notifications in Settings.")
                } else if viewModel.authorizationStatus == .notDetermined {
                    Text("Tap to request permission to send notifications.")
                }
            }

            Section("Notification Content") {
                HStack {
                    Text("Title")
                    TextField("Title", text: $viewModel.pushTitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Body")
                    TextField("Body", text: $viewModel.pushBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Payload")
                    TextField("Optional JSON", text: Binding(
                        get: { viewModel.pushPayload ?? "" },
                        set: { viewModel.pushPayload = $0.isEmpty ? nil : $0 }
                    ))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                }
            }

            Section("Options") {
                Toggle("Play sound", isOn: $viewModel.playSound)
                Toggle("Repeat", isOn: $viewModel.repeatNotification)
                Toggle("Delay (\(viewModel.repeatNotification ? "60s" : "10s"))", isOn: $viewModel.delay)
                    .disabled(viewModel.repeatNotification)
                Toggle("Increment app badge", isOn: $viewModel.increaseBadge)
            }

            Section {
                Button("Send push notification") {
                    viewModel.sendNotification()
                }
            }

            Section("App Badge") {
                Stepper("Badge Count: \(viewModel.badgeCount)", value: $viewModel.badgeCount, in: 0...999)

                Button("Clear Badge & Notifications") {
                    viewModel.clearBadge()
                }
            }

            Section {
                if viewModel.scheduledNotifications.isEmpty {
                    Text("No scheduled notifications")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.scheduledNotifications) { notification in
                        ScheduledNotificationRow(notification: notification)
                    }
                }

                Button("Cancel All Scheduled") {
                    viewModel.cancelPending()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Scheduled Notifications")
            }
        }
        .navigationTitle("Notification Tester")
        .onFirstAppear {
            await viewModel.onAppear()
        }
        .onReceive(refreshTimer) { _ in
            Task { await viewModel.refreshScheduledNotifications() }
        }
    }
}

/// A row view displaying information about a scheduled notification.
///
/// Shows the notification's title, body, scheduled fire time, and whether it repeats.
struct ScheduledNotificationRow: View {
    /// The scheduled notification item to display.
    let notification: ScheduledNotificationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notification.title)
                .font(.headline)
            Text(notification.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let fireDate = notification.fireDate {
                HStack(spacing: 4) {
                    Text("Fires at \(fireDate.formatted(date: .omitted, time: .standard))")
                    if notification.repeats {
                        Text("(repeats)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A model representing a scheduled notification in the notification center.
///
/// This type extracts relevant information from `UNNotificationRequest` objects
/// for display in the UI.
struct ScheduledNotificationItem: Identifiable, Equatable {
    /// The unique identifier for this notification request.
    let notificationId: String

    /// The title of the notification.
    let title: String

    /// The body text of the notification.
    let body: String

    /// The date and time when this notification will fire, if available.
    let fireDate: Date?

    /// Whether this notification repeats.
    let repeats: Bool

    var id: String { notificationId }
}

#Preview {
    NavigationStack {
        NotificationTesterView()
    }
}
