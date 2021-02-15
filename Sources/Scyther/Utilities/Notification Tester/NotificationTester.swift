//
//  NotificationTester.swift
//  
//
//  Created by Brandon Stillitano on 15/2/21.
//

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
}
