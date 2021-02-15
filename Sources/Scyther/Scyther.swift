//
//  Scyther.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

#if !os(macOS)
import UIKit

/// Optional delegate that can be implemented to allow an app/caller to know that certain actions have been performed. This `protocol`is not required to be implemented in order for Scyther to work properly, it should be used primarily as a UI convenience; i.e. When switching environments, show a `UIAlertController`
public protocol ScytherDelegate: class {
    func scyther(didSwitchToEnvironment environment: String)
}

public class Scyther {
    /// Private init to stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `Scyther` class.
    public static let instance = Scyther()
    
    /// Delegate instance for listening to key events and performing subsequent actions
    public weak var delegate: ScytherDelegate? = nil
    
    /// Indicates whether or not Scyther has been initialised by the client implementing the framework.
    internal var started: Bool = false
    
    /// Indicates whether the Scyther menu is currently being presented or not.
    internal var presented: Bool = false
    
    /// The gesture that is to be used to invoke the Scyther menu. Defaults to `shake`.
    internal var selectedGesture: ScytherGesture = .shake
    
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
    
    /// Developer options that will be displayed on the main manue
    public var developerOptions: [DeveloperOption] = []
    
    /// Initialises the Scyther library and sets the required data to properly intercept network calls and console logs.
    public func start() {
        /// Set data
        self.started = true
        
        /// Register `URLProtocol` class for network logging to intercept requests. Swizzling required because libraries like
        /// Alamofire don't use the shared NSURLSession instance but instead use their own instance.
        URLSessionConfiguration.swizzleDefaultSessionConfiguration()
        Logger.enable(true)
        
        /// Get IP Address and store it in singleton instance for display on the menu
        Logger.getIPAddress { (ipAddress) in
            Scyther.logger.ipAddress = ipAddress
        }
        
        /// Starts the console logger and allows it intercept `stderr` output from `NSLog`
//        ConsoleLogger.instance.start()
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
            print("🐛🐛🐛🐛🐛🐛🐛🐛🐛🐛\n\nCould not find a keyWindow to anchor to. The menu will not be shown. This is expected.\n\n🐛🐛🐛🐛🐛🐛🐛🐛🐛🐛")
            #endif
            return nil
        }
    }
    
    /// Convenience for logging a message to the console.
    fileprivate func logMessage(_ msg: String) {
        print("Scyther - [https://github.com/bstillitano/scyther]: \(msg)")
    }
}
#endif
