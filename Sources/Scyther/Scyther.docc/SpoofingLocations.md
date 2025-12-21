# Spoofing Locations

Test location-based features without physically moving.

@Metadata {
    @PageColor(green)
}

## Overview

Location spoofing allows you to fake GPS coordinates for testing location-based features. This is invaluable for testing:

- Geofencing logic
- Location-based content
- Maps and navigation
- Regional features
- Delivery/ride-sharing apps

## Enabling Location Spoofing

```swift
// Enable spoofing
Scyther.location.spoofingEnabled = true

// Set a location
Scyther.location.spoofedLocation = Location(
    id: "sydney",
    name: "Sydney, Australia",
    latitude: -33.8688,
    longitude: 151.2093
)
```

Once enabled, all `CLLocationManager` instances in your app will report the spoofed location.

## Preset Locations

Scyther includes 20+ major cities as presets:

```swift
// Use built-in presets
LocationSpoofer.instance.spoofedLocation = .sydney
LocationSpoofer.instance.spoofedLocation = .tokyo
LocationSpoofer.instance.spoofedLocation = .newYork
LocationSpoofer.instance.spoofedLocation = .london
LocationSpoofer.instance.spoofedLocation = .berlin
LocationSpoofer.instance.spoofedLocation = .paris
LocationSpoofer.instance.spoofedLocation = .sanFrancisco
LocationSpoofer.instance.spoofedLocation = .losAngeles
LocationSpoofer.instance.spoofedLocation = .dubai
LocationSpoofer.instance.spoofedLocation = .singapore
```

## Custom Locations

Create custom locations for specific testing scenarios:

```swift
let customLocation = Location(
    id: "office-hq",
    name: "Company Headquarters",
    latitude: 37.7749,
    longitude: -122.4194
)

Scyther.location.spoofedLocation = customLocation
```

## Developer Locations

Add locations that appear in the Scyther UI for your team:

```swift
// Add test locations for your app
LocationSpoofer.instance.addLocation(Location(
    id: "warehouse-a",
    name: "Warehouse A",
    latitude: 40.7128,
    longitude: -74.0060
))

LocationSpoofer.instance.addLocation(Location(
    id: "store-downtown",
    name: "Downtown Store",
    latitude: 40.7589,
    longitude: -73.9851
))

LocationSpoofer.instance.addLocation(Location(
    id: "customer-test",
    name: "Test Customer Address",
    latitude: 40.7484,
    longitude: -73.9857
))
```

These locations appear in the Scyther menu under **Location Spoofing**.

## Route Simulation

Simulate movement along predefined routes:

```swift
// Use built-in routes
LocationSpoofer.instance.spoofedRoute = .driveCityToSuburb
LocationSpoofer.instance.spoofedRoute = .walkAroundBlock
```

### Creating Custom Routes

```swift
let deliveryRoute = Route(
    id: "delivery-route",
    name: "Delivery Test Route",
    locations: [
        Location(id: "start", name: "Warehouse", latitude: 40.7128, longitude: -74.0060),
        Location(id: "stop1", name: "First Stop", latitude: 40.7200, longitude: -74.0000),
        Location(id: "stop2", name: "Second Stop", latitude: 40.7300, longitude: -73.9900),
        Location(id: "end", name: "Final Destination", latitude: 40.7400, longitude: -73.9800)
    ],
    interval: 5.0  // Seconds between location updates
)

LocationSpoofer.instance.addRoute(deliveryRoute)
```

## Disabling Spoofing

```swift
// Disable spoofing to return to real location
Scyther.location.spoofingEnabled = false
```

## How It Works

Scyther uses method swizzling to intercept `CLLocationManager` delegate calls. When spoofing is enabled:

1. Real location updates are suppressed
2. Spoofed coordinates are delivered to your location delegate
3. Your app behaves as if the device is at the spoofed location

> Note: Location spoofing works in the app process only. It doesn't affect other apps or system services.

## Testing Scenarios

### Geofencing

Test entering and exiting geofenced regions:

```swift
// Place user inside geofence
Scyther.location.spoofedLocation = Location(
    id: "inside-store",
    name: "Inside Store Geofence",
    latitude: storeLatitude,
    longitude: storeLongitude
)

// Then move outside
Scyther.location.spoofedLocation = Location(
    id: "outside-store",
    name: "Outside Store",
    latitude: storeLatitude + 0.01,
    longitude: storeLongitude + 0.01
)
```

### Regional Content

Test region-specific features:

```swift
// Test US content
LocationSpoofer.instance.spoofedLocation = .newYork

// Test EU content
LocationSpoofer.instance.spoofedLocation = .london

// Test APAC content
LocationSpoofer.instance.spoofedLocation = .tokyo
```

### Edge Cases

Test unusual locations:

```swift
// International Date Line
let dateLine = Location(id: "dateline", name: "Date Line", latitude: 0, longitude: 180)

// North Pole
let northPole = Location(id: "north-pole", name: "North Pole", latitude: 90, longitude: 0)

// Null Island (0,0)
let nullIsland = Location(id: "null-island", name: "Null Island", latitude: 0, longitude: 0)
```

## Best Practices

### 1. Clean Up

Always disable spoofing after testing:

```swift
override func tearDown() {
    Scyther.location.spoofingEnabled = false
}
```

### 2. Realistic Coordinates

Use real-world coordinates for meaningful tests, not arbitrary numbers.

### 3. Test Movement

Don't just test static locations - use routes to simulate user movement.

### 4. Consider Accuracy

The spoofed location reports perfect accuracy. If your app handles location uncertainty, test that separately.

## See Also

- ``LocationSpoofer``
- ``Location``
- ``Route``

