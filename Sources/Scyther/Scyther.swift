//
//  Scyther.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

#if !os(macOS)
import UIKit

/// Optional delegate that can be implemented to allow an app/caller to know that certain actions have been performed. This `protocol`is not required to be implemented in order for Scyther to work properly, it should be used primarily as a UI convenience; i.e. When switching environments, show a `UIAlertController`
public protocol ScytherDelegate: AnyObject {
    func scyther(didSwitchToEnvironment environment: String)
}

public class Scyther {
    /// Private init to stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `Scyther` class.
    public static let instance = Scyther()
    
    /// Delegate instance for listening to key events and performing subsequent actions
    public weak var delegate: ScytherDelegate? = nil
    
    /// Boolean value for controlling whether or not the Scyther library should be run on builds installed via the AppStore and builds that contain a production installation receipt. Must be set before calling `Scyther.instance.start`
    public var runsOnProductionBuilds: Bool = false

    /// Indicates whether or not Scyther has been initialised by the client implementing the framework.
    internal var started: Bool = false
    
    /// Indicates whether the Scyther menu is currently being presented or not.
    internal var presented: Bool = false
    
    /// The gesture that is to be used to invoke the Scyther menu. Defaults to `shake`.
    public var selectedGesture: ScytherGesture = .shake
    
    /// `Toggler` utility class. Used for local toggle/feature flag overrides.
    public static let toggler: Toggler = Toggler.instance
    
    /// `ConfigurationSwitcher` utility class. Used for local toggle/feature flag overrides.
    public static let configSwitcher: ConfigurationSwitcher = ConfigurationSwitcher.instance
    
    /// `Logger` utility class. Used for local network logging.
    public static let logger: Logger = Logger.instance
    
    /// `ConsoleLogger` utility class. Used for intercepting local console output.
    public static let consoleLogger: ConsoleLogger = ConsoleLogger.instance
    
    /// `NotificationTester` utility class. Used for testing push notification functionality.
    public static let notificationTester: NotificationTester = NotificationTester.instance
    
    /// `InterfaceToolkit` utility class. Used for overlaying UI Elements onto the running application.
    public static let interfaceToolkit: InterfaceToolkit = InterfaceToolkit.instance
    
    /// Developer options that will be displayed on the main menu
    public var developerOptions: [DeveloperOption] = []
    
    /// 64 Character device token registered with APNS. Example: 30eee4d53612de08c61477d4503b23220d76d74efed258230ef3536afd4504f2
    public var apnsToken: String?
    
    /// Variable length device token registerd with FCM. Example: dEoOEdh9yEy5sK-BeTxzJR:APA91bH0bNeYvYadpl98frTc6FYY1DbicXc40QrTDj5aOFxPNZF-JLEGvawxWl6g9GXgZod04_UV95zBlzdYFnxByHSCcySmzyrqfPk1IQC7aIfefBTL7a3FX9dQVNnG4x1igi317YUf
    public var fcmToken: String?
    
    /// Initialises the Scyther library and sets the required data to properly intercept network calls and console logs. This will not run on Production/AppStore builds if `runsOnProductionBuilds` is not set to true.
    public func start() {
        /// Check for production build
        guard !AppEnvironment.isAppStore || runsOnProductionBuilds else {
            return
        }
        
        /// Set data
        self.started = true
        
        /// Register `URLProtocol` class for network logging to intercept requests. Swizzling required because libraries like
        /// Alamofire don't use the shared NSURLSession instance but instead use their own instance.
        URLSessionConfiguration.swizzleDefaultSessionConfiguration()
        Logger.enable(true)
        
        /// Get IP Address and store it in singleton instance for display on the menu
        Logger.getIPAddress { (ipAddress) in
            Logger.instance.ipAddress = ipAddress
        }
        
        /// Starts the console logger and allows it intercept `stderr` output from `NSLog`
//        ConsoleLogger.instance.start()
        
        /// Sets up the interface toolkit plugins
        InterfaceToolkit.instance.start()
        
        /// Sets up location spoofing after a one second delay. Delay exists here to allow time for applications with a map view in their initial view state
        /// time to register for CLLocationManager updates. This is a bit hacky because of the way that map view registers its own delegate.
        let spoofingEnabled: Bool = LocationSpoofer.instance.spoofingEnabled
        LocationSpoofer.instance.spoofingEnabled = true
        LocationSpoofer.instance.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            LocationSpoofer.instance.spoofingEnabled = spoofingEnabled
        }
    }

    /// Convenience function for manually showing the Scyther menu. Would be used when no gesture is wanted to invoke the menu.
    public static func presentMenu(from viewController: UIViewController? = nil) {
        /// Check if Scyther has been started. If not, don't execute any code.
        guard Scyther.instance.started else {
            return
        }
        
        /// Check if Scyther is already showing the menu. If so, don't re-show the menu.
        guard !Scyther.instance.presented else {
            return
        }
        
        /// Construct our `MenuViewController` wrapped inside a `UINavigationController`.
        let viewModel = MenuViewModel()
        let menuViewController: MenuViewController = MenuViewController()
        menuViewController.configure(with: viewModel)
        let navigationController: UINavigationController = UINavigationController(rootViewController: menuViewController)
        
        /// Set data
        Scyther.instance.presented = true
        
        /// Check for a presenter (`UIViewController`) otherwise use the `presentingViewController` to present it within a `UINavigationController`.
        guard viewController == nil else {
            viewController?.present(navigationController, animated: true, completion: nil)
            return
        }
        Scyther.instance.presentingViewController?.present(navigationController, animated: true, completion: nil)
    }
    
    public static func dismissMenu(animated: Bool, completion: (() -> Void)? = nil) {
        /// Check if Scyther is showing the menu. If not, don't do anything, it's not Scythers to touch.
        guard Scyther.instance.presented else {
            return
        }
        
        /// Get topmost navigation controller and dismiss it
        guard let viewContoller: UIViewController = Scyther.instance.presentingViewController else {
            return
        }
        viewContoller.dismiss(animated: animated, completion: completion)
        Scyther.instance.presented = false
    }
}

extension Scyther {
    /// Determines the top most view controller within the running application and returns it as a usable `UIViewController` reference.
    fileprivate var presentingViewController: UIViewController? {
        if var topController = UIApplication.shared.keyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
            
        } else {
            #if DEBUG
            logMessage("Could not find a keyWindow to anchor to. The menu will not be shown. This is expected.")
            #endif
            return nil
        }
    }
}

/// Convenience for logging a message to the console.
internal func logMessage(_ msg: String) {
    print("🐛🐛🐛🐛🐛🐛🐛🐛🐛🐛\n\nScyther - [https://github.com/bstillitano/scyther]: \(msg)\n\n🐛🐛🐛🐛🐛🐛🐛🐛🐛🐛")
}
#endif
