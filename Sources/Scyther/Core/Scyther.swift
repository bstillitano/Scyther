//
//  Scyther.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

#if !os(macOS)
import UIKit
import SwiftUI

// MARK: - Delegate

/// Delegate for receiving Scyther events.
public protocol ScytherDelegate: AnyObject {
    func scytherDidSwitchServer(to serverId: String)
}

// MARK: - Scyther

/// Debug menu and developer tools for iOS apps.
public enum Scyther {

    // MARK: - State

    private static var _started = false
    private static var _presented = false

    /// Whether Scyther has been started.
    public static var isStarted: Bool { _started }

    /// Whether the menu is currently presented.
    public static var isPresented: Bool { _presented }

    /// Delegate for receiving Scyther events.
    public static weak var delegate: ScytherDelegate?

    /// Gesture used to invoke the menu. Set before calling `start()`.
    public static var invocationGesture: ScytherGesture = .shake

    // MARK: - Subsystems

    /// Feature flag management and local overrides.
    public static let featureFlags = FeatureFlags.shared

    /// Server/environment configuration switching.
    public static let servers = Servers.shared

    /// Network request logging.
    public static let network = Network.shared

    /// Push notification testing.
    public static let notifications = Notifications.shared

    /// Console output capture.
    public static let console = Console.shared

    /// UI overlay tools (grid, touch visualiser).
    public static let interface = Interface.shared

    /// Location spoofing.
    public static let location = LocationSpoofing.shared

    // MARK: - Configuration

    /// Custom developer options displayed in the menu.
    public static var developerOptions: [DeveloperOption] = []

    /// Custom environment variables shown in the Environment Variables screen.
    public static var environmentVariables: [String: String] = [:]

    /// APNS device token (64 character hex string).
    public static var apnsToken: String?

    /// FCM device token.
    public static var fcmToken: String?

    // MARK: - Lifecycle

    /// Starts Scyther and enables all debugging features.
    ///
    /// Call this early in your app's lifecycle, typically in `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// - Parameter allowProductionBuilds: If `true`, Scyther will run on App Store builds. Default is `false`.
    @MainActor
    public static func start(allowProductionBuilds: Bool = false) {
        guard !AppEnvironment.isAppStore || allowProductionBuilds else {
            return
        }

        _started = true

        Console.shared.startCapturing()
        Network.shared.startIntercepting()
        Interface.shared.setup()
        LocationSpoofing.shared.setup()
    }

    // MARK: - Menu

    /// Presents the Scyther debug menu.
    ///
    /// - Parameter viewController: Optional view controller to present from. If `nil`, presents from the topmost view controller.
    public static func showMenu(from viewController: UIViewController? = nil) {
        guard _started, !_presented else { return }

        let menu = UIHostingController(rootView: MenuView())
        let nav = UINavigationController(rootViewController: menu)

        _presented = true

        let presenter = viewController ?? topViewController
        presenter?.present(nav, animated: true)
    }

    /// Dismisses the Scyther debug menu.
    ///
    /// - Parameters:
    ///   - animated: Whether to animate the dismissal.
    ///   - completion: Called after dismissal completes.
    public static func hideMenu(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard _presented else { return }

        topViewController?.dismiss(animated: animated, completion: completion)
        _presented = false
    }

    // MARK: - Private

    private static var topViewController: UIViewController? {
        guard var top = keyWindow?.rootViewController else {
            #if DEBUG
            logMessage("Could not find a keyWindow to anchor to.")
            #endif
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

// MARK: - Logging

internal func logMessage(_ msg: String) {
    print("Scyther: \(msg)")
}

// MARK: - Subsystem Namespaces

/// Feature flag management.
public final class FeatureFlags {
    public static let shared = FeatureFlags()
    private init() {}

    private var defaultsKey: String { "scyther.featureFlags.overridesEnabled" }

    /// All registered feature flags.
    public private(set) var all: [FeatureToggle] = []

    /// Whether local overrides are enabled.
    public var localOverridesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Registers a feature flag.
    ///
    /// - Parameters:
    ///   - name: Unique identifier for the flag.
    ///   - remoteValue: The server-side value for this flag.
    ///   - abValue: Optional A/B test condition string.
    public func register(_ name: String, remoteValue: Bool, abValue: String? = nil) {
        all.removeAll { $0.name == name }
        all.append(FeatureToggle(name: name, remoteValue: remoteValue, abValue: abValue))
    }

    /// Returns whether a feature flag is enabled.
    ///
    /// - Parameter name: The flag name.
    /// - Returns: The effective value (local override if enabled, otherwise remote).
    public func isEnabled(_ name: String) -> Bool {
        guard let flag = all.first(where: { $0.name == name }) else {
            return false
        }
        return localOverridesEnabled ? flag.value : flag.remoteValue
    }

    /// Sets the local override value for a flag.
    public func setLocalValue(_ value: Bool, for name: String) {
        guard var flag = all.first(where: { $0.name == name }) else { return }
        flag.localValue = value
    }

    /// Gets the local override value for a flag.
    internal func localValue(for name: String) -> Bool? {
        all.first { $0.name == name }?.localValue
    }

    /// Gets the remote value for a flag.
    internal func remoteValue(for name: String) -> Bool {
        all.first { $0.name == name }?.remoteValue ?? false
    }
}

/// Server/environment configuration.
public actor Servers {
    public static let shared = Servers()
    private init() {}

    private var defaultsKey: String { "scyther.servers.currentId" }

    /// All registered server configurations.
    public private(set) var all: [ServerConfiguration] = [] {
        didSet {
            if currentId.isEmpty, let first = all.first {
                currentId = first.id
            }
        }
    }

    /// The currently selected server ID.
    public var currentId: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// The currently selected server configuration.
    public var current: ServerConfiguration? {
        all.first { $0.id == currentId }
    }

    /// Environment variables for the current server.
    public var variables: [String: String] {
        current?.variables ?? [:]
    }

    /// Registers a server configuration.
    public func register(id: String, variables: [String: String] = [:]) {
        all.removeAll { $0.id == id }
        all.append(ServerConfiguration(id: id, variables: variables))
    }

    /// Registers multiple server configurations.
    public func register(_ configurations: [ServerConfiguration]) {
        for config in configurations {
            register(id: config.id, variables: config.variables)
        }
    }

    /// Switches to a different server.
    public func select(_ id: String) {
        currentId = id
        Scyther.delegate?.scytherDidSwitchServer(to: id)
    }
}

/// Network logging.
public final class Network {
    public static let shared = Network()
    private init() {}

    internal func startIntercepting() {
        NetworkHelper.instance.start()
    }

    /// The device's current IP address.
    public var ipAddress: String {
        get async { await NetworkHelper.instance.ipAddress }
    }
}

/// Push notification testing.
public final class Notifications {
    public static let shared = Notifications()
    private init() {}

    /// Schedules a local test notification.
    public func scheduleTest(title: String = "Test Notification",
                             body: String = "This is a test notification.",
                             delay: TimeInterval = 5,
                             sound: Bool = true,
                             incrementBadge: Bool = false) {
        NotificationTester.instance.scheduleNotification(
            withTitle: title,
            withBody: body,
            withSound: sound,
            withDelay: delay,
            andIncreaseBadge: incrementBadge
        )
    }

    /// All logged notifications.
    public var logged: [PushNotification] {
        NotificationTester.instance.notifications
    }
}

/// Console output capture.
public final class Console {
    public static let shared = Console()
    private init() {}

    internal func startCapturing() {
        ConsoleLogger.instance.start()
    }

    /// Stops capturing console output.
    public func stopCapturing() {
        ConsoleLogger.instance.stop()
    }

    /// Clears all captured logs.
    public func clear() {
        ConsoleLogger.instance.clear()
    }

    /// All captured log entries.
    public var logs: [ConsoleLogEntry] {
        ConsoleLogger.instance.allLogs
    }
}

/// UI overlay tools.
public final class Interface {
    public static let shared = Interface()
    private init() {}

    internal func setup() {
        InterfaceToolkit.instance.start()
    }

    /// Shows or hides the grid overlay.
    public var gridOverlayEnabled: Bool {
        get { GridOverlay.instance.enabled }
        set { GridOverlay.instance.enabled = newValue }
    }

    /// Shows or hides the touch visualiser.
    public var touchVisualizerEnabled: Bool {
        get { TouchVisualiser.instance.enabled }
        set {
            if newValue {
                TouchVisualiser.instance.start()
            } else {
                TouchVisualiser.instance.stop()
            }
        }
    }
}

/// Location spoofing.
public final class LocationSpoofing {
    public static let shared = LocationSpoofing()
    private init() {}

    internal func setup() {
        let wasEnabled = LocationSpoofer.instance.spoofingEnabled
        LocationSpoofer.instance.spoofingEnabled = true
        LocationSpoofer.instance.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            LocationSpoofer.instance.spoofingEnabled = wasEnabled
        }
    }

    /// Whether location spoofing is enabled.
    public var spoofingEnabled: Bool {
        get { LocationSpoofer.instance.spoofingEnabled }
        set { LocationSpoofer.instance.spoofingEnabled = newValue }
    }

    /// The current spoofed location.
    public var spoofedLocation: Location {
        get { LocationSpoofer.instance.spoofedLocation }
        set { LocationSpoofer.instance.spoofedLocation = newValue }
    }
}
#endif
