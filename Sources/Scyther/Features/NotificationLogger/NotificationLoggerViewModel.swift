//
//  NotificationLoggerViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model managing the notification logger display.
///
/// `NotificationLoggerViewModel` is responsible for loading, sorting, and transforming
/// logged push notifications from ``NotificationTester`` into a format suitable for
/// display in the UI. It automatically refreshes when new notifications are received
/// via `NotificationCenter` notifications.
///
/// ## Features
///
/// - Loads all logged push notifications from ``NotificationTester``
/// - Sorts notifications by received date (newest first)
/// - Transforms raw notification data into display-friendly ``NotificationLogItem`` objects
/// - Provides JSON formatting for additional data and raw payloads
/// - Responds to new notification events for real-time updates
///
/// ## Usage
///
/// This view model is typically used with ``NotificationLoggerView``:
///
/// ```swift
/// struct NotificationLoggerView: View {
///     @StateObject private var viewModel = NotificationLoggerViewModel()
///
///     var body: some View {
///         List {
///             ForEach(viewModel.notifications) { notification in
///                 // Display notification details
///             }
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///         .onReceive(NotificationCenter.default.publisher(for: .NotificationLoggerLoggedData)) { _ in
///             Task { await viewModel.refresh() }
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Published Properties
///
/// - ``notifications``
///
/// ### Lifecycle Methods
///
/// - ``onFirstAppear()``
/// - ``refresh()``
///
/// ### Private Methods
///
/// - ``loadNotifications()``
@MainActor
class NotificationLoggerViewModel: ViewModel {
    /// The array of logged notifications to display.
    ///
    /// This array is sorted by received date (newest first) and contains
    /// transformed notification data ready for UI presentation.
    @Published var notifications: [NotificationLogItem] = []

    /// Called when the view first appears.
    ///
    /// Loads the initial set of notifications from ``NotificationTester``.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadNotifications()
    }

    /// Refreshes the notification list.
    ///
    /// This method should be called when the app receives a notification
    /// that new push data has been logged, typically via `NotificationCenter`.
    func refresh() async {
        await loadNotifications()
    }

    /// Loads and transforms notifications from ``NotificationTester``.
    ///
    /// This private method fetches all logged notifications, sorts them by
    /// received date (newest first), and transforms them into ``NotificationLogItem``
    /// objects for display.
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
