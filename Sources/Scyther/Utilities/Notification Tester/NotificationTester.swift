//
//  NotificationTester.swift
//
//
//  Created by Brandon Stillitano on 15/2/21.
//

#if !os(macOS)
import UIKit
import UserNotifications

public class NotificationTester {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() {
        //Set Data
        notificationCenter.getNotificationSettings { [weak self] (settings) in
            self?.notificationsAllowed = settings.authorizationStatus == .authorized
        }
    }

    /// An initialised, shared instance of the `NotificationTester` class.
    static let instance = NotificationTester()

    /// Reference to the local `UNUserNotificationCenter` singleton.
    private let notificationCenter = UNUserNotificationCenter.current()

    /// `Bool` value representing whether or not notification permissions have been granted on the running device.
    public var notificationsAllowed: Bool = false

    /// Schedules a local notification that will be delivered in a given time from now
    /// - Parameters:
    ///   - title: Title of the notification that will be sent
    ///   - body: Body/Description of the notification that will be sent
    ///   - withSound: Boolean value representing whether or not a sound should be played
    ///   - delay: Time in seconds until this notitifcaiton should be fired (default is 2 seconds)
    ///   - repeats: Boolean value representing whether or not the notification should repeat
    ///   - increaseBadge: Boolean value representing whether or not the app badge should increment
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
    }
}
#endif
