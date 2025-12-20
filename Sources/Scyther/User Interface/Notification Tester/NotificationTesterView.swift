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

    var body: some View {
        List {
            Section("Send a test") {
                LabeledContent("Title", value: viewModel.pushTitle)
                LabeledContent("Body", value: viewModel.pushBody)
                LabeledContent("Payload", value: viewModel.pushPayload ?? "None")

                Toggle("Play sound", isOn: $viewModel.playSound)
                Toggle("Repeat", isOn: $viewModel.repeatNotification)
                Toggle("Delay (\(viewModel.repeatNotification ? "60s" : "10s"))", isOn: $viewModel.delay)
                    .disabled(viewModel.repeatNotification)
                Toggle("Increment app badge", isOn: $viewModel.increaseBadge)

                Button("Send push notification") {
                    viewModel.sendNotification()
                }
            }

            Section("App badge") {
                Button("Increment app badge") {
                    viewModel.incrementBadge()
                }

                Button("Decrease app badge") {
                    viewModel.decreaseBadge()
                }

                Button("Clear app badge") {
                    viewModel.clearBadge()
                }

                Button("Cancel scheduled notifications") {
                    viewModel.cancelPending()
                }
            }
        }
        .navigationTitle("Notification Tester")
    }
}

class NotificationTesterSwiftUIViewModel: ViewModel {
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
    }

    @MainActor
    func incrementBadge() {
        let badgeCount = UIApplication.shared.applicationIconBadgeNumber
        UIApplication.shared.applicationIconBadgeNumber = badgeCount + 1
    }

    @MainActor
    func decreaseBadge() {
        let badgeCount = UIApplication.shared.applicationIconBadgeNumber
        UIApplication.shared.applicationIconBadgeNumber = max(0, badgeCount - 1)
    }

    @MainActor
    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    @MainActor
    func cancelPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

#Preview {
    NavigationStack {
        NotificationTesterView()
    }
}
