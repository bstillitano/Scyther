# Working with Feature Flags

Register, check, and override feature flags at runtime for rapid testing.

@Metadata {
    @PageColor(green)
}

## Overview

Feature flags allow you to toggle functionality without recompiling. Scyther's feature flag system lets you:

- Register flags from your remote configuration system
- Check flag values throughout your app
- Override flags locally for testing
- Support complex boolean expressions

## Registering Feature Flags

After fetching your remote configuration (e.g., from Firebase Remote Config, LaunchDarkly, etc.), register the flags with Scyther:

```swift
// Register individual flags
Scyther.featureFlags.register("new_checkout_flow", remoteValue: true)
Scyther.featureFlags.register("dark_mode_v2", remoteValue: false)
Scyther.featureFlags.register("premium_features", remoteValue: true)
```

## Checking Flag Values

Use ``FeatureFlags/isEnabled(_:)`` to check if a feature is enabled:

```swift
if Scyther.featureFlags.isEnabled("new_checkout_flow") {
    showNewCheckoutFlow()
} else {
    showLegacyCheckoutFlow()
}
```

The method considers both the remote value and any local override, with local overrides taking precedence.

## Local Overrides

Enable local overrides to allow toggling flags from the Scyther UI:

```swift
// Enable the override toggle in the UI
Scyther.featureFlags.localOverridesEnabled = true
```

You can also set overrides programmatically:

```swift
// Force a flag on for testing
Scyther.featureFlags.setLocalValue(true, for: "dark_mode_v2")

// Clear a specific override
Scyther.featureFlags.clearLocalValue(for: "dark_mode_v2")

// Clear all overrides
Scyther.featureFlags.clearAllLocalValues()
```

## Accessing All Flags

Iterate over all registered flags:

```swift
for flag in Scyther.featureFlags.all {
    print("Flag: \(flag.name)")
    print("  Remote: \(flag.remoteValue)")
    print("  Local: \(String(describing: flag.localValue))")
    print("  Effective: \(Scyther.featureFlags.isEnabled(flag.name))")
}
```

## Boolean Expressions

Scyther supports complex boolean expressions for advanced flag logic:

```swift
// Check compound conditions
let showFeature = Scyther.featureFlags.isEnabled(
    "premium_features AND new_checkout_flow"
)

// OR conditions
let useNewUI = Scyther.featureFlags.isEnabled(
    "new_ui_v2 OR beta_tester"
)

// NOT conditions
let showLegacy = Scyther.featureFlags.isEnabled(
    "NOT new_checkout_flow"
)

// Complex expressions with parentheses
let eligible = Scyther.featureFlags.isEnabled(
    "(premium_user OR beta_tester) AND NOT maintenance_mode"
)
```

## Best Practices

### 1. Register Early

Register flags as early as possible, ideally right after fetching remote config:

```swift
func applicationDidFinishLaunching() {
    Scyther.start()

    RemoteConfig.shared.fetch { [weak self] in
        self?.registerFeatureFlags()
    }
}
```

### 2. Use Descriptive Names

```swift
// Good
Scyther.featureFlags.register("checkout_apple_pay_enabled", remoteValue: true)

// Avoid
Scyther.featureFlags.register("flag1", remoteValue: true)
```

### 3. Clean Up Old Flags

Remove flags that are no longer in use to keep the list manageable in the UI.

## See Also

- ``FeatureFlags``
- ``FeatureToggle``

