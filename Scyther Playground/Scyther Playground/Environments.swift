//
//  Environments.swift
//  Scyther Playground
//
//  Created by Brandon Stillitano on 18/2/21.
//

import Foundation
import Scyther

enum Environments: String, CaseIterable {
    case production
    case sandbox

    var cookieDomain: String {
        switch self {
        case .production:
            return "app.scyher.com"
        case .sandbox:
            return "sandbox.scyther.com"
        }
    }

    var rootURL: String {
        switch self {
        case .production:
            return "https://app.scyther.com/v1/"
        case .sandbox:
            return "https://sandbox.scyther.com/v1/"
        }
    }

    var supportURL: String {
        switch self {
        default:
            return "https://support.scyther.com/v1/"
        }
    }
    
    var authURL: String {
        switch self {
        case .production:
            return "https://app.scyther.com/auth/"
        case .sandbox:
            return "https://sandbox.scyther.com/auth/"
        }
    }
    
    var environmentVariables: [String: String] {
        return [
            "cookieDomain": "\(cookieDomain)",
            "rootURL": "\(rootURL)",
            "supportURL": "\(supportURL)",
            "authURL": "\(authURL)"
        ]
        
    }
}

class EnvironmentManger {
    /// Private init to stop re-initialisation
    private init() {
        /// Set default Scyther environment
        guard Scyther.configSwitcher.configuration.isEmpty else {
            return
        }
        Scyther.configSwitcher.configuration = Environments.production.rawValue
    }

    /// Singleton instance
    static var instance: EnvironmentManger = EnvironmentManger()

    /// The currently selected environment
    var environment: Environments {
        return Environments(rawValue: Scyther.configSwitcher.configuration) ?? .production
    }
}
