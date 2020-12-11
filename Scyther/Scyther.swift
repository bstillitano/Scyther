//
//  Scyther.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

import UIKit

public class Scyther {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `Scyther` class.
    public static let instance = Scyther()
    
    /// `Toggler` utlity class. Used for local toggle/feature flag overrides.
    public static let toggler: Toggler = Toggler.instance

    public static func presentMenu(from viewController: UIViewController? = nil) {
        /// Construct our `MenuViewController` wrapped inside a `UINavigationController`.
        let viewModel = MenuViewModel()
        let menuViewController: MenuViewController = MenuViewController()
        menuViewController.configure(with: viewModel)
        let navigationController: UINavigationController = UINavigationController(rootViewController: menuViewController)
        
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
        /// Get the `keyWindow` for the running application
        guard let keyWindow = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .map({$0 as? UIWindowScene})
                .compactMap({$0})
                .first?.windows
                .filter({$0.isKeyWindow}).first else {
            #if DEBUG
            print("🐛🐛🐛🐛🐛🐛🐛🐛🐛🐛\n\nCould not find a keyWindow to anchor to. The menu will not be shown. This is expected.\n\n🐛🐛🐛🐛🐛🐛🐛🐛🐛🐛")
            #endif
            return nil
        }
        
        /// Get the `rootViewController` for the running application and itterate over it's `presentedViewController` objects to determine the top most view controller.
        var rootViewController = keyWindow.rootViewController
        while let controller = rootViewController?.presentedViewController {
            rootViewController = controller
        }
        
        return rootViewController
    }
}
