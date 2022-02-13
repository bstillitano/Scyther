//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import UIKit

public extension UIApplication {
    private static var launchScreenPath: String {
        return "\(NSHomeDirectory())/Library/SplashBoard"
    }

    func clearLaunchScreenCache() {
        try? FileManager.default.removeItem(atPath: Self.launchScreenPath)
    }

    /// Display name for the running application
    var appName: String {
        return Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? ""
    }

    /// The current app version for the running application.
    var appVersion: String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// The current build number for the running application.
    var buildNumber: String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}
