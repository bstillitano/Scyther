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
                    Text(localized("Permission Status"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(viewModel.permissionStatusText)
                        .foregroundStyle(viewModel.permissionStatusColor)
                }

                if viewModel.authorizationStatus == .notDetermined {
                    Button(localized("Request Permission")) {
                        viewModel.requestPermission()
                    }
                } else if viewModel.authorizationStatus == .denied {
                    Button(localized("Open Settings")) {
                        viewModel.openSettings()
                    }
                }
            } header: {
                Text(localized("Push Notifications"))
            } footer: {
                if viewModel.authorizationStatus == .denied {
                    Text(localized("Permission was denied. You can enable notifications in Settings."))
                } else if viewModel.authorizationStatus == .notDetermined {
                    Text(localized("Tap to request permission to send notifications."))
                }
            }

            Section(localized("Notification Content")) {
                HStack {
                    Text(localized("Title"))
                    TextField(localized("Title"), text: $viewModel.pushTitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text(localized("Body"))
                    TextField(localized("Body"), text: $viewModel.pushBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text(localized("Payload"))
                    TextField(localized("Optional JSON"), text: Binding(
                        get: { viewModel.pushPayload ?? "" },
                        set: { viewModel.pushPayload = $0.isEmpty ? nil : $0 }
                    ))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                }
            }

            Section(localized("Options")) {
                Toggle(localized("Play sound"), isOn: $viewModel.playSound)
                Toggle(localized("Repeat"), isOn: $viewModel.repeatNotification)
                Toggle(localized("Delay (\(viewModel.repeatNotification ? "60s" : "10s"))"), isOn: $viewModel.delay)
                    .disabled(viewModel.repeatNotification)
                Toggle(localized("Increment app badge"), isOn: $viewModel.increaseBadge)
            }

            Section {
                Button(localized("Send Push Notification")) {
                    viewModel.sendNotification()
                }
            }

            Section(localized("App Badge")) {
                Stepper(localized("Badge Count: \(viewModel.badgeCount)"), value: $viewModel.badgeCount, in: 0...999)

                Button(localized("Clear Badge & Notifications")) {
                    viewModel.clearBadge()
                }
            }

            Section {
                if viewModel.scheduledNotifications.isEmpty {
                    Text(localized("No scheduled notifications"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.scheduledNotifications) { notification in
                        ScheduledNotificationRow(notification: notification)
                    }
                }

                Button(localized("Cancel All Scheduled")) {
                    viewModel.cancelPending()
                }
                .foregroundStyle(.red)
            } header: {
                Text(localized("Scheduled Notifications"))
            }
        }
        .navigationTitle(localized("Notification Tester"))
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
                    Text(localized("Fires at \(fireDate.formatted(date: .omitted, time: .standard))"))
                    if notification.repeats {
                        Text(localized("(repeats)"))
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
