//
//  FeatureToggle.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/12/20.
//

import Foundation

internal struct FeatureToggle {
    /**
     Public intialiser for `FeatureToggle` objects. Requires that a name and an optional `abValue` be passed in.
     
     - Parameters:
        - name: The name of the feature/toggle that is being
        - abValue: The conditional value that is used for this flag/toggle. Takes precedence over `localValue`.

     - Complexity: O(1)
     */
    public init(name: String, remoteValue: Bool, abValue: String? = nil) {
        self.name = name
        self.remoteValue = remoteValue
        self.abValue = abValue
    }

    /// String value that can be used to conditionally enable this flag/toggle based on certain criteria.
    private var abValue: String?

    /// String value that is used to reference this flag/toggle. Should be unique as `Toggler` instances will remove any previously declared values.
    internal var name: String

    /**
     Calculates the correct value that should be used based on the data contained within the `FeatureToggle`

     - Returns: A bool value representing the conditions that make up this `FeatureToggle`
     
     - Complexity: O(1)
     */
    internal var value: Bool {
        ///Check A/B next as this should take priority over any other values
        guard abValue == nil else {
            return ShuntingYardResolver.instance.evaluate(expression: abValue)
        }
        return localValue
    }

    /**
     The `UserDefaults` key that this `FeatureToggle` value is referred to as. This value is used when storing/reading from `UserDefaults` for the `localValue` value.

     - Returns: A string value representing the `name` value with `lowercased()` applied as well as all blank spaces replaced with an underscore and `toggler_local_value_` prefixed. For example, `Secret Feature` would become `toggler_local_value_secret_feature`
     
     - Complexity: O(1)
     */
    private var defaultsKey: String {
        return "Scyther_toggler_local_value_\(name.lowercased().replacingOccurences(of: [" "], with: "_"))"
    }

    /**
     The value that is returned from your remote server. Must be set when intialising this `FeatureToggle` value. Defaults to `false`
     
     - Returns: A bool value representing the remote value that was returned when fetching flags/toggles from your server.
     
     - Complexity: O(1)
     */
    internal var remoteValue: Bool = false

    /**
     Getter/Setter for this `FeatureToggle` object's local override. When setting this value it will write to `UserDefaults` using the `defaultsKey` value as the key.

     - Returns: A bool value representing whether or not the local value should be used when accessing this `FeatureToggle`.
     
     - Complexity: O(1)
     */
    internal var localValue: Bool {
        get {
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: defaultsKey)
        }
    }
}
