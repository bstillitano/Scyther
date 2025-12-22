//
//  ScytherExampleApp.swift
//  ScytherExample
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Scyther
import Security
@preconcurrency import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show notifications even when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

@main
struct ScytherExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private func loadRocketSimConnect() {
        #if DEBUG
        guard (Bundle(path: "/Applications/RocketSim.app/Contents/Frameworks/RocketSimConnectLinker.nocache.framework")?.load() == true) else {
            print("Failed to load linker framework")
            return
        }
        print("RocketSim Connect successfully linked")
        #endif
    }

    init() {
        // Start RocketSim
        loadRocketSimConnect()

        // Start Scyther
        Scyther.start()

        // Configure some example environment variables
        Scyther.environmentVariables = [
            "API_BASE_URL": "https://api.example.com",
            "APP_ENVIRONMENT": "development",
            "FEATURE_NEW_UI": "enabled"
        ]

        // Configure example server configurations
        Task {
            await Scyther.servers.register(id: "Development", variables: [
                "API_URL": "https://dev-api.example.com",
                "WS_URL": "wss://dev-ws.example.com",
                "CDN_URL": "https://dev-cdn.example.com",
                "DEBUG": "true",
                "LOG_LEVEL": "verbose"
            ])
            await Scyther.servers.register(id: "Staging", variables: [
                "API_URL": "https://staging-api.example.com",
                "WS_URL": "wss://staging-ws.example.com",
                "CDN_URL": "https://staging-cdn.example.com",
                "DEBUG": "true",
                "LOG_LEVEL": "info"
            ])
            await Scyther.servers.register(id: "Production", variables: [
                "API_URL": "https://api.example.com",
                "WS_URL": "wss://ws.example.com",
                "CDN_URL": "https://cdn.example.com",
                "DEBUG": "false",
                "LOG_LEVEL": "error"
            ])

            // Register example feature flags
            Scyther.featureFlags.register("dark_mode_v2", remoteValue: true)
            Scyther.featureFlags.register("new_checkout_flow", remoteValue: false)
            Scyther.featureFlags.register("enhanced_search", remoteValue: true)
            Scyther.featureFlags.register("push_notifications", remoteValue: true)
            Scyther.featureFlags.register("biometric_login", remoteValue: false)
            Scyther.featureFlags.register("analytics_v3", remoteValue: true)
            Scyther.featureFlags.register("experimental_ui", remoteValue: false)
            Scyther.featureFlags.register("offline_mode", remoteValue: true)
        }

        // Setup example cookies
        setupDemoCookies()

        // Setup example keychain items
        setupDemoKeychainItems()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    // MARK: - Demo Data Setup

    private func setupDemoCookies() {
        let cookieStorage = HTTPCookieStorage.shared

        // Session cookie
        if let sessionCookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "session_id",
            .value: "abc123def456",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(86400 * 7) // 7 days
        ]) {
            cookieStorage.setCookie(sessionCookie)
        }

        // User preferences cookie
        if let prefsCookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "user_prefs",
            .value: "theme=dark&lang=en",
            .expires: Date().addingTimeInterval(86400 * 30) // 30 days
        ]) {
            cookieStorage.setCookie(prefsCookie)
        }

        // Analytics cookie
        if let analyticsCookie = HTTPCookie(properties: [
            .domain: "analytics.example.com",
            .path: "/",
            .name: "_ga",
            .value: "GA1.2.1234567890.1234567890",
            .expires: Date().addingTimeInterval(86400 * 365) // 1 year
        ]) {
            cookieStorage.setCookie(analyticsCookie)
        }

        // Auth token cookie
        if let authCookie = HTTPCookie(properties: [
            .domain: "api.example.com",
            .path: "/api",
            .name: "auth_token",
            .value: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(86400) // 1 day
        ]) {
            cookieStorage.setCookie(authCookie)
        }
    }

    private func setupDemoKeychainItems() {
        // Demo API key
        saveToKeychain(
            service: "com.example.scyther",
            account: "api_key",
            data: "sk_live_1234567890abcdef"
        )

        // Demo access token
        saveToKeychain(
            service: "com.example.scyther",
            account: "access_token",
            data: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0"
        )

        // Demo refresh token
        saveToKeychain(
            service: "com.example.scyther",
            account: "refresh_token",
            data: "rt_abcdef123456"
        )

        // Demo user credentials
        saveToKeychain(
            service: "com.example.scyther.auth",
            account: "demo_user@example.com",
            data: "encrypted_password_hash"
        )
    }

    private func saveToKeychain(service: String, account: String, data: String) {
        guard let dataBytes = data.data(using: .utf8) else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: dataBytes,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
