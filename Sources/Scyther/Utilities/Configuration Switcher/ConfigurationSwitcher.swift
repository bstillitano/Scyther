//
//  ConfigurationSwitcher.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import Foundation

public class ConfigurationSwitcher {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `ConfigurationSwitcher` class.
    static let instance = ConfigurationSwitcher()

    /// Array of `ServerConfiguration` objects representing the environments that have been set by the client instantiating the `Scyther` library.
    internal var configurations: [ServerConfiguration] = [] {
        didSet {
            /// Set default value
            guard configuration.isEmpty else {
                return
            }
            guard let newConfig = configurations.first else {
                return
            }
            configuration = newConfig.identifier
        }
    }
    
    /**
     The `UserDefaults` key that `ConfigurationSwitcher` uses to determine what environment identifier is the current one.
     
     - Returns: A string value representing the global value which is used to store state in `UserDefaults` for ConfigurationSwitcher.
     
     - Complexity: O(1)
     */
    internal var defaultsKey: String {
        return "configuration_switcher_identity"
    }

    /**
     Getter/Setter for the current `ServerConfiguration` identity. When setting this value it will write to `UserDefaults` using the `defaultsKey` value as the key.

     - Returns: A string value representing the indetity of the currently selected `ServerConfiguration`
     
     - Complexity: O(1)
     */
    public var configuration: String {
        get {
            return UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: defaultsKey)
        }
    }
    
    /**
     Getter for the current `ServerConfiguration` environment variables.
     
     - Returns: A dictionary value representing the identity of the currently selected `ServerConfiguration`
     
     - Complexity: O(1)
     */
    public var environmentVariables: [String: String] {
        return configurations.first(where: { $0.identifier == configuration })?.variables ?? [:]
    }
    
    /**
     Setter for a given `ServerConfiguration` object. Must use this setter as `ConfigurationSwitcher.init()` is marked `internal` for API purposes. Calling this function will remove all duplicate `ServerConfiguration` objects based on the `identifier` that is passed in.
     
     - Parameters:
        - identifier: The name of the environment that the caller is attempting to set the value of.
        - variables: The dictionary that the caller/client's application has configured for this environment.
     
     - Complexity: O(*n*) where *n* is the number of `ServerConfiguration` objects inside the `configurations` array that have  the `identifier`
     */
    public func configureEnvironment(withIdentifier identifier: String, variables: [String: String] = [:]) {
        /// Remove Duplicate Toggles
        configurations.removeAll(where: { $0.identifier == identifier })

        /// Construct & insert environment into local array
        let environment: ServerConfiguration = ServerConfiguration(identifier: identifier,
                                                                   variables: variables)
        configurations.append(environment)
    }
}
