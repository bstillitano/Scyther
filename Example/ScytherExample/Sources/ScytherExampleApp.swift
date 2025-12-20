//
//  ScytherExampleApp.swift
//  ScytherExample
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Scyther
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

@main
struct ScytherExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Start Scyther
        Scyther.instance.start()

        // Configure some example environment variables
        Scyther.instance.customEnvironmentVariables = [
            "API_BASE_URL": "https://api.example.com",
            "APP_ENVIRONMENT": "development",
            "FEATURE_NEW_UI": "enabled"
        ]
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
