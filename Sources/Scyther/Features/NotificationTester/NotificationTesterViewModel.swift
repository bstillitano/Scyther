//
//  NotificationTesterViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI
import UserNotifications

/// View model managing the state and logic for the notification tester interface.
///
/// `NotificationTesterViewModel` provides a comprehensive interface for testing and
/// managing local push notifications in debug builds. It handles permission requests,
/// notification scheduling, badge management, and monitoring of pending notifications.
///
/// ## Features
///
/// - **Permission Management**: Check, request, and monitor notification authorization status
/// - **Notification Scheduling**: Configure and send test notifications with custom content
/// - **Badge Management**: Control app badge count and clear delivered notifications
/// - **Scheduled Monitoring**: Track and display all pending notification requests
/// - **Flexible Options**: Support for sounds, delays, repeating notifications, and badge increments
///
/// ## Usage
///
/// This view model is typically used with ``NotificationTesterView``:
///
/// ```swift
/// struct NotificationTesterView: View {
///     @StateObject private var viewModel = NotificationTesterViewModel()
///
///     var body: some View {
///         List {
///             Section {
///                 Text("Permission: \(viewModel.permissionStatusText)")
///                     .foregroundStyle(viewModel.permissionStatusColor)
///
///                 if viewModel.authorizationStatus == .notDetermined {
///                     Button("Request Permission") {
///                         viewModel.requestPermission()
///                     }
///                 }
///             }
///
///             Section("Content") {
///                 TextField("Title", text: $viewModel.pushTitle)
///                 TextField("Body", text: $viewModel.pushBody)
///             }
///
///             Button("Send Notification") {
///                 viewModel.sendNotification()
///             }
///         }
///         .onFirstAppear {
///             await viewModel.onAppear()
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Published Properties
///
/// - ``authorizationStatus``
/// - ``badgeCount``
/// - ``pushTitle``
/// - ``pushBody``
/// - ``pushPayload``
/// - ``playSound``
/// - ``delay``
/// - ``repeatNotification``
/// - ``increaseBadge``
/// - ``scheduledNotifications``
///
/// ### Computed Properties
///
/// - ``permissionStatusText``
/// - ``permissionStatusColor``
///
/// ### Lifecycle Methods
///
/// - ``onAppear()``
///
/// ### Public Methods
///
/// - ``refreshScheduledNotifications()``
/// - ``checkAuthorizationStatus()``
/// - ``requestPermission()``
/// - ``openSettings()``
/// - ``sendNotification()``
/// - ``clearBadge()``
/// - ``cancelPending()``
@MainActor
class NotificationTesterViewModel: ViewModel {
    // MARK: - Published Properties

    /// The current notification authorization status.
    ///
    /// This property is updated automatically when checking or requesting permissions.
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The current app badge count.
    ///
    /// Setting this value automatically updates `UIApplication.shared.applicationIconBadgeNumber`.
    @Published var badgeCount: Int = 0 {
        didSet {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
    }

    /// The title for the test notification.
    @Published var pushTitle: String = "Scyther Notification"

    /// The body text for the test notification.
    @Published var pushBody: String = "This is a dummy notification powered by Scyther."

    /// Optional JSON payload to include with the test notification.
    @Published var pushPayload: String? = nil

    /// Whether the test notification should play a sound.
    @Published var playSound: Bool = true

    /// Whether to delay the notification (10s for one-time, 60s for repeating).
    ///
    /// This is automatically set to `true` when ``repeatNotification`` is enabled.
    @Published var delay: Bool = false

    /// Whether the notification should repeat every 60 seconds.
    ///
    /// When enabled, this automatically sets ``delay`` to `true`.
    @Published var repeatNotification: Bool = false {
        didSet {
            if repeatNotification {
                delay = true
            }
        }
    }

    /// Whether to increment the badge count when sending the notification.
    @Published var increaseBadge: Bool = true

    /// The list of currently scheduled notifications.
    ///
    /// This array is automatically refreshed periodically and when notifications are scheduled or canceled.
    @Published var scheduledNotifications: [ScheduledNotificationItem] = []

    // MARK: - Computed Properties

    /// A human-readable text representation of the current authorization status.
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

    /// The color to display for the current authorization status.
    ///
    /// - Returns: Green for authorized states, red for denied, secondary for undetermined.
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

    // MARK: - Lifecycle Methods

    /// Called when the view appears.
    ///
    /// Checks authorization status, refreshes scheduled notifications,
    /// and syncs the badge count with the current app state.
    override func onAppear() async {
        await super.onAppear()
        await checkAuthorizationStatus()
        await refreshScheduledNotifications()
        await MainActor.run {
            badgeCount = UIApplication.shared.applicationIconBadgeNumber
        }
    }

    // MARK: - Public Methods

    /// Refreshes the list of scheduled notifications.
    ///
    /// Fetches all pending notification requests from `UNUserNotificationCenter`
    /// and transforms them into ``ScheduledNotificationItem`` objects.
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

    /// Checks and updates the current notification authorization status.
    ///
    /// This method queries `UNUserNotificationCenter` for the current notification
    /// settings and updates ``authorizationStatus``.
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Requests notification permission from the user.
    ///
    /// Requests authorization for alerts, sounds, and badges. After the user
    /// responds, ``authorizationStatus`` is automatically updated.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                await self?.checkAuthorizationStatus()
            }
        }
    }

    /// Opens the app's settings page in the Settings app.
    ///
    /// This is typically used when notification permission has been denied,
    /// allowing the user to manually enable notifications.
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Sends a test notification with the configured settings.
    ///
    /// Uses the current values of ``pushTitle``, ``pushBody``, ``pushPayload``,
    /// ``playSound``, ``delay``, ``repeatNotification``, and ``increaseBadge``
    /// to schedule a notification via ``NotificationTester``.
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

    /// Clears the app badge count and removes all delivered notifications.
    ///
    /// Sets ``badgeCount`` to 0 and removes all notifications from the
    /// notification center's delivered list.
    func clearBadge() {
        badgeCount = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Cancels all pending notification requests.
    ///
    /// Removes all scheduled notifications and refreshes the
    /// ``scheduledNotifications`` list.
    func cancelPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        Task {
            await refreshScheduledNotifications()
        }
    }
}
