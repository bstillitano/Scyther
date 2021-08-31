//
//  PushNotification.swift
//
//
//  Created by Brandon Stillitano on 31/8/21.
//

import Foundation

public struct PushNotification {
    public init() { }

    public var receivedAt: Date?
    public var aps: PushNotificationAPS = PushNotificationAPS()
    public var additionalData: [AnyHashable: Any] = [:]
    public var rawPayload: [AnyHashable: Any] = [:]
}

public struct PushNotificationAPS {
    public init() { }

    public var alert: PushNotificationAPSAlert = PushNotificationAPSAlert()
    public var category: String?
    public var contentAvailable: Int?
    public var badge: Int?
    public var sound: String?
}

public struct PushNotificationAPSAlert {
    public init() { }

    public var title: String?
    public var subtitle: String?
    public var body: String?
}
