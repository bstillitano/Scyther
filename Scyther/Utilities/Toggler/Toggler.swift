//
//  Toggler.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

import Foundation

public class Toggler {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `Toggler` class.
    static let instance = Toggler()

    /**
     Array of `Toggle` objects representing the flags/toggles that have been set by the client instantiating the `Scyther` library.
     */
    internal var toggles: [Toggle] = []

    /**
     The `UserDefaults` key that `Toggler` uses to determine whether or not values should be overriden/intercepted.
     
     - Returns: A string value representing the global value which is used to store state in `UserDefaults` for Toggler.
     
     - Complexity: O(1)
     */
    private var defaultsKey: String {
        return "toggler_local_overrides_enabled"
    }

    /**
     Getter/Setter for this `Toggle` object's local override. When setting this value it will write to `UserDefaults` using the `defaultsKey` value as the key.

     - Returns: A bool value representing the whether or not the local value should be used when accessing this `Toggle`.
     
     - Complexity: O(1)
     */
    public var localOverridesEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: defaultsKey)
        }
    }

    /**
     Getter for a given `Toggle` object's `value`. Must use this getter as `name` is marked `internal` for API purposes.
     
     - Returns: A bool value representing whether or not the local value should be used when accessing this `Toggle`.
     
     - Parameter name: The name of the toggle that the caller is attempting to access the `value` of.
     
     - Complexity: O(*n*) where *n* is the first index of `name` in the array of toggles.
     */
    public func value(forToggle name: String) -> Bool {
        /// Check for toggle in local array
        guard let toggle = toggles.first(where: { $0.name == name }) else {
            return false
        }
        
        /// Check for local overrides otherwise return the remote value for the toggle
        guard localOverridesEnabled else {
            return toggle.remoteValue
        }
        
        /// Return calculated `value` variable from `toggle`
        return toggle.value
    }
    
    /**
     Getter for a given `Toggle` object's `localvalue`. Must use this getter as `name` is marked `internal` for API purposes.
     
     - Returns: A bool value representing whether or not the local value should be used when accessing this `Toggle`.
     
     - Parameter name: The name of the toggle that the caller is attempting to access the `value` of.
     
     - Complexity: O(*n*) where *n* is the first index of `name` in the array of toggles.
     */
    internal func localValue(forToggle name: String) -> Bool {
        /// Check for toggle in local array
        guard let toggle = toggles.first(where: { $0.name == name }) else {
            return false
        }
        
        /// Check for local value
        return toggle.localValue
    }


    /**
     Setter for a given `Toggle` object's `value`. Must use this setter as `Toggler.init()` is marked `internal` for API purposes. Calling this function will remove all duplicate `Toggle` objects based on the `name` that is passed in.
     
     - Parameters:
        - name: The name of the toggle that the caller is attempting to set the `value` of.
        - remoteValue: The value that the caller/client's remote server has configured for this flag/toggle.
        - abValue: The conditional value that is used for this flag/toggle. Takes precedence over `localValue`.
     
     - Complexity: O(*n*) where *n* is the number of `Toggle` objects inside the `toggles` array that have  the `name`
     */
    public func configureToggle(withName name: String, remoteValue: Bool, abValue: String? = nil) {
        /// Remove Duplicate Toggles
        toggles.removeAll(where: { $0.name == name })

        /// Construct & insert toggle into local array
        let toggle: Toggle = Toggle(name: name, remoteValue: remoteValue, abValue: abValue)
        toggles.append(toggle)
    }

    public func setLocalValue(value: Bool, forToggleWithName name: String) {
        print("RERRERE")
        /// Check for toggle in local array
        guard var toggle = toggles.first(where: { $0.name == name }) else {
            return
        }

        /// Set Toggle Value
        toggle.localValue = value
    }
}
