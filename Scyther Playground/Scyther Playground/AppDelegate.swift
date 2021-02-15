//
//  AppDelegate.swift
//  Scyther Playground
//
//  Created by Brandon Stillitano on 12/2/21.
//

import Scyther
import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        /// Run Scyther only on non AppStore builds to avoid introducing potential security issues into our app.
        if !AppEnvironment.isAppStore {
            //Setup Networking
            Scyther.instance.start()
//            Scyther.instance.delegate = self
//            for environment in Environments.allCases {
//                Scyther.configSwitcher.configureEnvironment(withIdentifier: environment.rawValue, variables: environment.environmentVariables)
//            }
//
//            //Setup Developer Tools
//            var deeplinkOption: DeveloperOption = DeveloperOption()
//            deeplinkOption.name = "Deeplink Tester"
//            deeplinkOption.icon = UIImage(systemImage: "link")
//            deeplinkOption.viewController = DeeplinksViewController()
//            Scyther.instance.developerOptions.append(deeplinkOption)
        }

        //Register for Push
        registerForPushNotifications()

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list, .banner, .badge, .sound])
    }
}

extension AppDelegate {
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            UNUserNotificationCenter.current().delegate = self
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate { }
