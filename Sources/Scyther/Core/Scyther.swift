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

/// A protocol for receiving callbacks when Scyther events occur.
///
/// Implement this protocol to respond to events such as server configuration changes.
///
/// ## Example
///
/// ```swift
/// class AppCoordinator: ScytherDelegate {
///     func scytherDidSwitchServer(to serverId: String) {
///         // Reconfigure your networking layer
///         APIClient.shared.baseURL = getBaseURL(for: serverId)
///     }
/// }
/// ```
public protocol ScytherDelegate: AnyObject {
    /// Called when the user switches to a different server configuration.
    ///
    /// Use this callback to update your app's networking configuration, clear caches,
    /// or perform any other necessary reconfiguration.
    ///
    /// - Parameter serverId: The identifier of the newly selected server.
    func scytherDidSwitchServer(to serverId: String)
}

// MARK: - Scyther

/// The main entry point for the Scyther debugging toolkit.
///
/// Scyther provides a comprehensive suite of debugging tools for iOS applications,
/// including network logging, feature flag management, location spoofing, and more.
///
/// ## Getting Started
///
/// Start Scyther early in your app's lifecycle:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         Scyther.start()
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///     }
/// }
/// ```
///
/// ## Available Subsystems
///
/// Access Scyther's features through these subsystems:
///
/// - ``featureFlags``: Manage and override feature flags
/// - ``servers``: Switch between server environments
/// - ``network``: Access network logging data
/// - ``notifications``: Test push notifications
/// - ``console``: View captured console output
/// - ``interface``: Enable UI debugging overlays
/// - ``location``: Spoof device location
///
/// ## Topics
///
/// ### Lifecycle
/// - ``start(allowProductionBuilds:)``
/// - ``showMenu(from:)``
/// - ``hideMenu(animated:completion:)``
///
/// ### State
/// - ``isStarted``
/// - ``isPresented``
///
/// ### Subsystems
/// - ``featureFlags``
/// - ``servers``
/// - ``network``
/// - ``notifications``
/// - ``console``
/// - ``interface``
/// - ``location``
///
/// ### Configuration
/// - ``developerOptions``
/// - ``environmentVariables``
/// - ``invocationGesture``
/// - ``delegate``
@MainActor
public enum Scyther {

    // MARK: - State

    private nonisolated(unsafe) static var _started = false
    private static var _presented = false

    /// Whether Scyther has been started.
    public nonisolated static var isStarted: Bool { _started }

    /// Whether the menu is currently presented.
    public static var isPresented: Bool { _presented }

    /// Delegate for receiving Scyther events.
    nonisolated(unsafe) public static weak var delegate: ScytherDelegate?

    /// Gesture used to invoke the menu. Set before calling `start()`.
    nonisolated(unsafe) public static var invocationGesture: ScytherGesture = .shake

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

    /// Appearance overrides (color scheme, dynamic type, high contrast).
    public static let appearance = Appearance.shared

    /// Deep link testing.
    public static let deepLinks = DeepLinks.shared

    // MARK: - Configuration

    /// Custom developer options displayed in the menu.
    nonisolated(unsafe) public static var developerOptions: [DeveloperOption] = []

    /// Custom environment variables shown in the Environment Variables screen.
    nonisolated(unsafe) public static var environmentVariables: [String: String] = [:]

    /// APNS device token (64 character hex string).
    nonisolated(unsafe) public static var apnsToken: String?

    /// FCM device token.
    nonisolated(unsafe) public static var fcmToken: String?

    // MARK: - Lifecycle

    /// Starts Scyther and enables all debugging features.
    ///
    /// Call this early in your app's lifecycle, typically in `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// - Parameter allowProductionBuilds: If `true`, Scyther will run on App Store builds. Default is `false`.
    public static func start(allowProductionBuilds: Bool = false) {
        guard !AppEnvironment.isAppStore || allowProductionBuilds else {
            return
        }

        _started = true

        Console.shared.startCapturing()
        Network.shared.startIntercepting()
        Interface.shared.setup()
        LocationSpoofing.shared.setup()
        Appearance.shared.setup()
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

/// Manages feature flags with support for local overrides.
///
/// Use `FeatureFlags` to register feature flags from your remote configuration system
/// and allow developers to override them locally during testing.
///
/// ## Registering Feature Flags
///
/// Register flags after fetching them from your remote configuration:
///
/// ```swift
/// // After fetching remote config
/// Scyther.featureFlags.register("new_checkout_flow", remoteValue: true)
/// Scyther.featureFlags.register("dark_mode_v2", remoteValue: false)
/// ```
///
/// ## Checking Flag Values
///
/// Use ``isEnabled(_:)`` to check the effective value of a flag:
///
/// ```swift
/// if Scyther.featureFlags.isEnabled("new_checkout_flow") {
///     showNewCheckoutFlow()
/// }
/// ```
///
/// ## Topics
///
/// ### Registration
/// - ``register(_:remoteValue:)``
///
/// ### Querying
/// - ``isEnabled(_:)``
/// - ``all``
///
/// ### Local Overrides
/// - ``localOverridesEnabled``
/// - ``setLocalValue(_:for:)``
@MainActor
public final class FeatureFlags: Sendable {
    /// The shared feature flags instance.
    public static let shared = FeatureFlags()
    private init() {}

    private var defaultsKey: String { "scyther.featureFlags.overridesEnabled" }

    /// All registered feature flags.
    ///
    /// This array contains all flags that have been registered via ``register(_:remoteValue:abValue:)``.
    public private(set) var all: [FeatureToggle] = []

    /// Whether local overrides are enabled.
    ///
    /// When `true`, the Scyther UI allows users to toggle feature flags locally.
    /// The ``isEnabled(_:)`` method will return local override values when available.
    public var localOverridesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Registers a feature flag.
    ///
    /// Call this method after fetching your remote configuration to make flags
    /// available in the Scyther UI. Registering a flag with the same name will
    /// replace any existing registration.
    ///
    /// - Parameters:
    ///   - name: Unique identifier for the flag.
    ///   - remoteValue: The server-side value for this flag.
    public func register(_ name: String, remoteValue: Bool) {
        all.removeAll { $0.name == name }
        all.append(FeatureToggle(name: name, remoteValue: remoteValue))
    }

    /// Returns whether a feature flag is enabled.
    ///
    /// This method returns the effective value considering local overrides:
    /// - If ``localOverridesEnabled`` is `true` and a local override exists, returns the override.
    /// - Otherwise, returns the remote value.
    ///
    /// - Parameter name: The flag name to check.
    /// - Returns: `true` if the flag is enabled, `false` otherwise. Returns `false` for unknown flags.
    public func isEnabled(_ name: String) -> Bool {
        guard let flag = all.first(where: { $0.name == name }) else {
            return false
        }
        return localOverridesEnabled ? flag.value : flag.remoteValue
    }

    /// Sets the local override value for a flag.
    ///
    /// - Parameters:
    ///   - value: The override value to set.
    ///   - name: The flag name to override.
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

/// Manages server and environment configurations for easy switching.
///
/// Use `Servers` to register different backend environments (development, staging, production)
/// and switch between them at runtime without recompiling.
///
/// ## Registering Servers
///
/// ```swift
/// await Scyther.servers.register(id: "development", variables: [
///     "API_URL": "https://dev-api.example.com",
///     "DEBUG": "true"
/// ])
/// await Scyther.servers.register(id: "production", variables: [
///     "API_URL": "https://api.example.com",
///     "DEBUG": "false"
/// ])
/// ```
///
/// ## Responding to Server Changes
///
/// Implement ``ScytherDelegate`` to respond when the user switches servers:
///
/// ```swift
/// class AppDelegate: ScytherDelegate {
///     func scytherDidSwitchServer(to serverId: String) {
///         // Reconfigure networking, clear caches, etc.
///     }
/// }
/// ```
///
/// - Note: This type is an actor for thread-safe access to server configurations.
public actor Servers {
    /// The shared servers instance.
    public static let shared = Servers()
    private init() {}

    private var defaultsKey: String { "scyther.servers.currentId" }

    /// All registered server configurations.
    ///
    /// Contains all servers registered via ``register(id:variables:)`` or ``register(_:)``.
    public private(set) var all: [ServerConfiguration] = [] {
        didSet {
            if currentId.isEmpty, let first = all.first {
                currentId = first.id
            }
        }
    }

    /// The identifier of the currently selected server.
    ///
    /// This value is persisted across app launches using `UserDefaults`.
    public var currentId: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// The currently selected server configuration.
    ///
    /// Returns `nil` if no server matching ``currentId`` is registered.
    public var current: ServerConfiguration? {
        all.first { $0.id == currentId }
    }

    /// Environment variables for the current server.
    ///
    /// Convenience accessor for `current?.variables`. Returns an empty dictionary
    /// if no server is selected.
    public var variables: [String: String] {
        current?.variables ?? [:]
    }

    /// Registers a server configuration.
    ///
    /// If a server with the same ID already exists, it will be replaced.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the server (e.g., "development", "staging", "production").
    ///   - variables: Key-value pairs of environment variables for this server.
    public func register(id: String, variables: [String: String] = [:]) {
        all.removeAll { $0.id == id }
        all.append(ServerConfiguration(id: id, variables: variables))
    }

    /// Registers multiple server configurations at once.
    ///
    /// - Parameter configurations: An array of server configurations to register.
    public func register(_ configurations: [ServerConfiguration]) {
        for config in configurations {
            register(id: config.id, variables: config.variables)
        }
    }

    /// Switches to a different server configuration.
    ///
    /// This method updates ``currentId`` and notifies ``Scyther/delegate`` of the change.
    ///
    /// - Parameter id: The identifier of the server to switch to.
    public func select(_ id: String) {
        currentId = id
        Scyther.delegate?.scytherDidSwitchServer(to: id)
    }
}

/// Provides access to network logging data.
///
/// The `Network` subsystem automatically intercepts and logs all HTTP requests
/// made through `URLSession` when Scyther is started.
///
/// ## Accessing Network Data
///
/// ```swift
/// // Get the device's IP address
/// let ip = await Scyther.network.ipAddress
/// ```
///
/// - Note: Network interception is enabled automatically when ``Scyther/start(allowProductionBuilds:)`` is called.
@MainActor
public final class Network: Sendable {
    /// The shared network instance.
    public static let shared = Network()
    private init() {}

    internal func startIntercepting() {
        NetworkHelper.instance.start()
    }

    /// The device's current IP address.
    ///
    /// Returns the device's external IP address as reported by a network lookup service.
    public var ipAddress: String {
        get async { await NetworkHelper.instance.ipAddress }
    }
}

/// Provides push notification testing capabilities.
///
/// Use `Notifications` to schedule test notifications and view logged notification payloads.
///
/// ## Scheduling Test Notifications
///
/// ```swift
/// Scyther.notifications.scheduleTest(
///     title: "Order Shipped!",
///     body: "Your order #12345 has shipped.",
///     delay: 5
/// )
/// ```
///
/// ## Viewing Logged Notifications
///
/// ```swift
/// for notification in Scyther.notifications.logged {
///     print(notification.aps.alert.title)
/// }
/// ```
@MainActor
public final class Notifications: Sendable {
    /// The shared notifications instance.
    public static let shared = Notifications()
    private init() {}

    /// Schedules a local test notification.
    ///
    /// Use this method to test your app's notification handling without needing
    /// to send a real push notification from a server.
    ///
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: The notification body text.
    ///   - delay: Seconds to wait before showing the notification.
    ///   - sound: Whether to play the default notification sound.
    ///   - incrementBadge: Whether to increment the app's badge number.
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

    /// All logged push notifications received by the app.
    ///
    /// Contains notifications captured since Scyther was started.
    public var logged: [PushNotification] {
        NotificationTester.instance.notifications
    }
}

/// Captures and displays console output.
///
/// The `Console` subsystem redirects `stdout` and `stderr` to capture all
/// `print()` statements and console output for viewing in the Scyther UI.
///
/// ## Viewing Console Output
///
/// ```swift
/// for entry in Scyther.console.logs {
///     print("\(entry.timestamp): \(entry.message)")
/// }
/// ```
///
/// - Note: Console capture is enabled automatically when ``Scyther/start(allowProductionBuilds:)`` is called.
@MainActor
public final class Console: Sendable {
    /// The shared console instance.
    public static let shared = Console()
    private init() {}

    internal func startCapturing() {
        ConsoleLogger.instance.start()
    }

    /// Stops capturing console output.
    ///
    /// Call this if you need to temporarily disable console capture.
    public func stopCapturing() {
        ConsoleLogger.instance.stop()
    }

    /// Clears all captured log entries.
    public func clear() {
        ConsoleLogger.instance.clear()
    }

    /// All captured console log entries.
    public var logs: [ConsoleLogEntry] {
        ConsoleLogger.instance.allLogs
    }
}

/// Provides UI debugging overlay tools.
///
/// The `Interface` subsystem offers visual debugging aids including a grid overlay
/// for checking alignment and a touch visualiser for recording interactions.
///
/// ## Enabling Grid Overlay
///
/// ```swift
/// Scyther.interface.gridOverlayEnabled = true
/// ```
///
/// ## Enabling Touch Visualiser
///
/// ```swift
/// Scyther.interface.touchVisualizerEnabled = true
/// ```
@MainActor
public final class Interface: Sendable {
    /// The shared interface instance.
    public static let shared = Interface()
    private init() {}

    internal func setup() {
        InterfaceToolkit.instance.start()
    }

    /// Whether the grid overlay is visible.
    ///
    /// When enabled, displays a customizable grid over the app's UI for
    /// verifying element alignment and spacing.
    public var gridOverlayEnabled: Bool {
        get { GridOverlay.instance.enabled }
        set { GridOverlay.instance.enabled = newValue }
    }

    /// Whether touch visualisation is enabled.
    ///
    /// When enabled, displays visual indicators where the user touches the screen.
    /// Useful for screen recordings and demonstrations.
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

/// Provides location spoofing capabilities for testing location-based features.
///
/// The `LocationSpoofing` subsystem intercepts `CLLocationManager` calls to return
/// fake coordinates, allowing you to test location-dependent features without
/// physically moving.
///
/// ## Enabling Location Spoofing
///
/// ```swift
/// Scyther.location.spoofingEnabled = true
/// Scyther.location.spoofedLocation = Location(
///     name: "Sydney Opera House",
///     latitude: -33.8568,
///     longitude: 151.2153
/// )
/// ```
///
/// - Important: Location spoofing uses method swizzling on `CLLocationManager`.
///   This is intended for development and testing only.
@MainActor
public final class LocationSpoofing: Sendable {
    /// The shared location spoofing instance.
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

    /// Whether location spoofing is currently enabled.
    ///
    /// When `true`, `CLLocationManager` will return ``spoofedLocation`` instead
    /// of the device's actual location.
    public var spoofingEnabled: Bool {
        get { LocationSpoofer.instance.spoofingEnabled }
        set { LocationSpoofer.instance.spoofingEnabled = newValue }
    }

    /// The location to report when spoofing is enabled.
    ///
    /// Set this to the coordinates you want `CLLocationManager` to return.
    public var spoofedLocation: Location {
        get { LocationSpoofer.instance.spoofedLocation }
        set { LocationSpoofer.instance.spoofedLocation = newValue }
    }
}

/// Provides appearance override capabilities for testing UI under different conditions.
///
/// The `Appearance` subsystem allows you to override system appearance settings
/// at runtime without changing device settings:
/// - Color scheme (light/dark mode)
/// - High contrast mode (iOS 17+)
/// - Dynamic Type text size
///
/// ## Forcing Dark Mode
///
/// ```swift
/// Scyther.appearance.colorScheme = .dark
/// ```
///
/// ## Testing Large Text
///
/// ```swift
/// Scyther.appearance.contentSizeCategory = .accessibilityExtraLarge
/// ```
///
/// ## Resetting to System Defaults
///
/// ```swift
/// Scyther.appearance.reset()
/// ```
@MainActor
public final class Appearance: Sendable {
    /// The shared appearance instance.
    public static let shared = Appearance()
    private init() {}

    internal func setup() {
        AppearanceOverrides.instance.registerForSceneNotifications()
        AppearanceOverrides.instance.applyAllOverrides()
    }

    /// The current color scheme override.
    ///
    /// Set to `.light` or `.dark` to force a specific appearance,
    /// or `.system` to follow the device setting.
    public var colorScheme: ColorSchemeOverride {
        get { AppearanceOverrides.instance.colorScheme }
        set { AppearanceOverrides.instance.colorScheme = newValue }
    }

    /// Whether high contrast mode is enabled.
    ///
    /// When `true`, the system uses increased contrast colors.
    /// Requires iOS 17+ to take effect.
    public var highContrastEnabled: Bool {
        get { AppearanceOverrides.instance.highContrastEnabled }
        set { AppearanceOverrides.instance.highContrastEnabled = newValue }
    }

    /// The content size category override for Dynamic Type.
    ///
    /// Set to a specific category to test how your app responds to different text sizes.
    /// Set to `nil` to use the system default.
    public var contentSizeCategory: UIContentSizeCategory? {
        get { AppearanceOverrides.instance.contentSizeCategory }
        set { AppearanceOverrides.instance.contentSizeCategory = newValue }
    }

    /// Resets all appearance overrides to system defaults.
    public func reset() {
        AppearanceOverrides.instance.resetToDefaults()
    }
}

// MARK: - Deep Links Facade

/// Provides a simplified interface for deep link testing.
///
/// Use this to configure preset deep links for quick testing:
///
/// ```swift
/// Scyther.deepLinks.presets = [
///     DeepLinkPreset(name: "Home", url: "myapp://home"),
///     DeepLinkPreset(name: "Profile", url: "myapp://profile/123"),
/// ]
/// ```
@MainActor
public final class DeepLinks: Sendable {
    /// The shared deep links instance.
    public static let shared = DeepLinks()
    private init() {}

    /// Preset deep links shown in the tester UI.
    ///
    /// Configure these to provide quick access to commonly-used deep links.
    public var presets: [DeepLinkPreset] {
        get { DeepLinkTester.instance.presets }
        set { DeepLinkTester.instance.presets = newValue }
    }

    /// History of tested deep links.
    public var history: [DeepLinkHistoryEntry] {
        DeepLinkTester.instance.history
    }

    /// Opens a deep link URL.
    ///
    /// - Parameter urlString: The URL string to open.
    /// - Returns: A result indicating success or failure.
    @discardableResult
    public func open(_ urlString: String) async -> Result<Void, DeepLinkError> {
        await DeepLinkTester.instance.open(urlString)
    }

    /// Clears the deep link history.
    public func clearHistory() {
        DeepLinkTester.instance.clearHistory()
    }
}
#endif
