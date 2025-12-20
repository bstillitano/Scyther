//
//  PushNotification.swift
//
//
//  Created by Brandon Stillitano on 31/8/21.
//

import Foundation

/// A structured representation of an Apple Push Notification Service (APNS) push notification.
///
/// This type models the standard APNS payload structure, including the `aps` dictionary
/// and any custom data fields sent alongside the notification.
///
/// ## Topics
/// ### Creating a Push Notification
/// - ``init()``
///
/// ### Notification Data
/// - ``receivedAt``
/// - ``aps``
/// - ``additionalData``
/// - ``rawPayload``
public struct PushNotification {
    /// Creates a new empty push notification.
    public init() { }

    /// The date and time when this notification was received by the application.
    public var receivedAt: Date?

    /// The Apple Push Notification service data, containing alert, badge, sound, and other standard fields.
    public var aps: PushNotificationAPS = PushNotificationAPS()

    /// Any custom key-value pairs included in the notification payload outside of the `aps` dictionary.
    public var additionalData: [String: Any] = [:]

    /// The complete, unprocessed notification payload as received from APNS.
    public var rawPayload: [String: Any] = [:]
}

/// The standard APNS dictionary containing notification presentation and behavior settings.
///
/// This structure represents the `aps` dictionary in an APNS payload, which contains
/// fields that control how the notification is displayed and handled by iOS.
///
/// ## Topics
/// ### Creating APS Data
/// - ``init()``
///
/// ### Alert Information
/// - ``alert``
///
/// ### Notification Behavior
/// - ``category``
/// - ``contentAvailable``
/// - ``badge``
/// - ``sound``
public struct PushNotificationAPS {
    /// Creates a new empty APS dictionary.
    public init() { }

    /// The alert content to display to the user.
    public var alert: PushNotificationAPSAlert = PushNotificationAPSAlert()

    /// The notification category identifier, used to determine which action buttons to show.
    public var category: String?

    /// Indicates whether this is a background notification. A value of `1` means content is available for background download.
    public var contentAvailable: Int?

    /// The number to display on the app's badge. Set to `0` to remove the badge.
    public var badge: Int?

    /// The name of the sound file to play when the notification is delivered, or `"default"` for the default sound.
    public var sound: String?
}

/// The alert content of a push notification.
///
/// This structure contains the user-visible text content of a notification alert,
/// including the title, subtitle, and body message.
///
/// ## Topics
/// ### Creating Alert Content
/// - ``init()``
///
/// ### Alert Text
/// - ``title``
/// - ``subtitle``
/// - ``body``
public struct PushNotificationAPSAlert {
    /// Creates a new empty alert.
    public init() { }

    /// A short string displayed as the notification title.
    public var title: String?

    /// Additional text displayed below the title (iOS 10+).
    public var subtitle: String?

    /// The main message content of the notification.
    public var body: String?
}
