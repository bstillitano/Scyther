//
//  Scyther.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

#if !os(macOS)
import UIKit

public class Scyther {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `Scyther` class.
    public static let instance = Scyther()
    
    /// Indicates whether or not Scyther has been initialised by the client implementing the framework.
    fileprivate var started: Bool = true
    
    /// Indicates whether the Scyther menu is currently being presented or not.
    internal var presented: Bool = false
    
    /// The gesture that is to be used to invoke the Scyther menu. Defaults to `shake`.
    internal var selectedGesture: ScytherGesture = .shake
    
    /// `Toggler` utlity class. Used for local toggle/feature flag overrides.
    public static let toggler: Toggler = Toggler.instance
    
    /// `ConfigurationSwitcher` utlity class. Used for local toggle/feature flag overrides.
    public static let configSwitcher: ConfigurationSwitcher = ConfigurationSwitcher.instance

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
        
        /// Set Data
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
}
#endif
