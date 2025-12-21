//
//  NotificationTester.swift

//
//
//  Created by Brandon Stillitano on 15/2/21.

//

#if !os(macOS)

import UIKit
import UserNotifications

/// A singleton utility for testing and logging push notifications.
///
/// `NotificationTester` provides functionality to schedule local test notifications
/// and process incoming push notifications for debugging purposes. It maintains a log
/// of all notifications received during the app session.
///
/// Use the shared ``instance`` to access notification testing features:
///
/// ```swift
/// NotificationTester.instance.scheduleNotification(
///     withTitle: "Test Notification",
///     withBody: "This is a test"
/// )
/// ```
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
///
/// ### Notification Permissions
/// - ``notificationsAllowed``
///
/// ### Notification History
/// - ``notifications``
///
/// ### Scheduling Notifications
/// - ``scheduleNotification(withTitle:withBody:withSound:withDelay:withRepeat:andIncreaseBadge:)``
///
/// ### Processing Notifications
/// - ``processNotification(_:)``
@MainActor
public final class NotificationTester: Sendable {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() {

        //Set Data
        notificationCenter.getNotificationSettings { [weak self] (settings) in
            self?.notificationsAllowed = settings.authorizationStatus == .authorized
        }
    }

    /// The shared singleton instance of `NotificationTester`.
    ///
    /// Use this instance to access all notification testing and logging functionality.
    static let instance = NotificationTester()

    /// Reference to the local `UNUserNotificationCenter` singleton.
    private let notificationCenter = UNUserNotificationCenter.current()

    /// Indicates whether notification permissions have been granted.
    ///
    /// This value is updated when the notification center's authorization status is checked.
    /// It will be `true` when the authorization status is `.authorized`, and `false` otherwise.
    public var notificationsAllowed: Bool = false

    /// An array of all notifications received or scheduled during this session.
    ///
    /// This includes both push notifications received from APNS and local notifications
    /// scheduled through Scyther. The array persists only for the current app session
    /// and is cleared when the app terminates.
    internal var notifications: [PushNotification] = []

    /// Schedules a local notification for testing purposes.
    ///
    /// Creates and schedules a local notification with customizable content and behavior.
    /// The notification will be delivered after the specified delay and optionally repeat.
    /// All scheduled notifications are automatically logged to the notification history.
    ///
    /// - Parameters:
    ///   - title: The title text displayed in the notification. Defaults to "Scyther Notification".
    ///   - body: The body text displayed in the notification. Defaults to "This is a dummy notification powered by Scyther.".
    ///   - withSound: Whether to play a sound when the notification is delivered. Defaults to `true`.
    ///   - delay: The delay in seconds before the notification is delivered. Defaults to 2 seconds.
    ///   - repeats: Whether the notification should repeat indefinitely. Defaults to `false`.
    ///   - increaseBadge: Whether to increment the app badge count. Defaults to `true`.
    ///
    /// - Note: The notification is logged immediately and will appear in the notification logger
    ///   even before it's delivered to the user.
    internal func scheduleNotification(withTitle title: String = "Scyther Notification",
                                       withBody body: String = "This is a dummy notification powered by Scyther.",
                                       withSound: Bool = true,
                                       withDelay delay: TimeInterval = 2,
                                       withRepeat repeats: Bool = false,
                                       andIncreaseBadge increaseBadge: Bool = true) {
        //Setup Notification Content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = withSound ? .default : .none
        content.badge = increaseBadge ? UIApplication.shared.applicationIconBadgeNumber + 1 as NSNumber : nil

        //Setup Trigger
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay,
                                                        repeats: repeats)

        //Schedule Notification
        let identifier = "Local_Scyther_Notification_\(Int.random(in: 0...99999))"
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content,
                                            trigger: trigger)
        notificationCenter.add(request, withCompletionHandler: nil)

        //Log locally scheduled notification
        logLocalNotification(title: title, body: body, sound: withSound, badge: content.badge as? Int)
    }

    /// Logs a locally scheduled notification so it appears in the notification logger
    private func logLocalNotification(title: String, body: String, sound: Bool, badge: Int?) {
        var notificationApsAlert = PushNotificationAPSAlert()
        notificationApsAlert.title = title
        notificationApsAlert.body = body

        var notificationAps = PushNotificationAPS()
        notificationAps.alert = notificationApsAlert
        notificationAps.sound = sound ? "default" : nil
        notificationAps.badge = badge

        var notification = PushNotification()
        notification.receivedAt = Date()
        notification.aps = notificationAps
        notification.additionalData = ["source": "Scyther Local Notification"]
        notification.rawPayload = [
            "aps": [
                "alert": ["title": title, "body": body],
                "sound": sound ? "default" : nil,
                "badge": badge as Any
            ],
            "source": "Scyther Local Notification"
        ]

        notifications.append(notification)
        NotificationCenter.default.post(name: .NotificationLoggerLoggedData, object: nil)
    }
    
    /// Processes and logs an incoming push notification from APNS.
    ///
    /// Parses the notification payload and extracts all standard APNS fields (title, body, badge, etc.)
    /// as well as any custom data. The processed notification is added to the notification history
    /// and a notification is posted to `NotificationCenter` to alert observers.
    ///
    /// Call this method from your app delegate when a push notification is received:
    ///
    /// ```swift
    /// func application(_ application: UIApplication,
    ///                  didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
    ///     NotificationTester.instance.processNotification(userInfo)
    /// }
    /// ```
    ///
    /// - Parameter userInfo: The notification payload dictionary received from APNS.
    public func processNotification(_ userInfo: [AnyHashable : Any]) {
        //Breakdown APNS Notification
        let aps: [String: Any] = userInfo["aps"] as? [String: Any] ?? [:]
        let apsAlert: [String: Any] = aps["alert"] as? [String: Any] ?? [:]
        let additionalData: [String: Any] = userInfo.filter({($0.key as? String ?? "") != "aps"}) as? [String: Any] ?? [:]

        //Construct Alert
        var notificationApsAlert: PushNotificationAPSAlert = PushNotificationAPSAlert()
        notificationApsAlert.title = apsAlert["title"] as? String
        notificationApsAlert.body = apsAlert["body"] as? String
        notificationApsAlert.subtitle = apsAlert["subtitle"] as? String
        
        //Construct APS Object
        var notificationAps: PushNotificationAPS = PushNotificationAPS()
        notificationAps.alert = notificationApsAlert
        notificationAps.category = aps["category"] as? String
        notificationAps.sound = aps["sound"] as? String
        notificationAps.badge = aps["badge"] as? Int
        notificationAps.contentAvailable = aps["content-available"] as? Int
        
        //Construct Notification
        var notification: PushNotification = PushNotification()
        notification.receivedAt = Date()
        notification.aps = notificationAps
        notification.rawPayload = userInfo as? [String: Any] ?? [:]
        notification.additionalData = additionalData
        
        //Append Data
        notifications.append(notification)
        
        //Post Notification
        NotificationCenter.default.post(name: .NotificationLoggerLoggedData, object: nil)
    }
}

/// Extension providing notification names for the notification logging system.
public extension NSNotification.Name {
    /// Posted when a new push notification has been logged.
    ///
    /// This notification is posted whenever ``NotificationTester`` logs a new notification,
    /// either from APNS or from a locally scheduled test notification. Observers can listen
    /// for this notification to update their UI when new notifications arrive.
    static let NotificationLoggerLoggedData = Notification.Name("NotificationLoggerLoggedData")
}
#endif
