//
//  NotificationTesterView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import UserNotifications

struct NotificationTesterView: View {
    @StateObject private var viewModel = NotificationTesterSwiftUIViewModel()

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

struct ScheduledNotificationRow: View {
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

struct ScheduledNotificationItem: Identifiable, Equatable {
    let notificationId: String
    let title: String
    let body: String
    let fireDate: Date?
    let repeats: Bool

    var id: String { notificationId }
}

class NotificationTesterSwiftUIViewModel: ViewModel {
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var badgeCount: Int = 0 {
        didSet {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
    }
    @Published var pushTitle: String = "Scyther Notification"
    @Published var pushBody: String = "This is a dummy notification powered by Scyther."
    @Published var pushPayload: String? = nil
    @Published var playSound: Bool = true
    @Published var delay: Bool = false
    @Published var repeatNotification: Bool = false {
        didSet {
            if repeatNotification {
                delay = true
            }
        }
    }
    @Published var increaseBadge: Bool = true
    @Published var scheduledNotifications: [ScheduledNotificationItem] = []

    var permissionStatusText: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not Determined"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }

    var permissionStatusColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .secondary
        @unknown default:
            return .secondary
        }
    }

    override func onAppear() async {
        await super.onAppear()
        await checkAuthorizationStatus()
        await refreshScheduledNotifications()
        await MainActor.run {
            badgeCount = UIApplication.shared.applicationIconBadgeNumber
        }
    }

    @MainActor
    func refreshScheduledNotifications() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        scheduledNotifications = requests.map { request in
            let title = request.content.title.isEmpty ? "(No title)" : request.content.title
            let body = request.content.body.isEmpty ? "(No body)" : request.content.body

            var fireDate: Date? = nil
            var repeats = false

            if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                fireDate = trigger.nextTriggerDate()
                repeats = trigger.repeats
            } else if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                fireDate = trigger.nextTriggerDate()
                repeats = trigger.repeats
            }

            return ScheduledNotificationItem(
                notificationId: request.identifier,
                title: title,
                body: body,
                fireDate: fireDate,
                repeats: repeats
            )
        }
    }

    @MainActor
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @MainActor
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                await self?.checkAuthorizationStatus()
            }
        }
    }

    @MainActor
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @MainActor
    func sendNotification() {
        let delayTime: TimeInterval = repeatNotification ? 60 : (delay ? 10 : 1)
        NotificationTester.instance.scheduleNotification(
            withTitle: pushTitle,
            withBody: pushBody,
            withSound: playSound,
            withDelay: delayTime,
            withRepeat: repeatNotification,
            andIncreaseBadge: increaseBadge
        )
        Task {
            await refreshScheduledNotifications()
        }
    }

    @MainActor
    func clearBadge() {
        badgeCount = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    @MainActor
    func cancelPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        Task {
            await refreshScheduledNotifications()
        }
    }
}

#Preview {
    NavigationStack {
        NotificationTesterView()
    }
}
