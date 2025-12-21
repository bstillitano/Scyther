# UI Debugging Tools

Visual aids to debug layout issues, create demos, and inspect your UI.

@Metadata {
    @PageColor(green)
}

## Overview

Scyther provides several visual debugging tools to help you identify layout issues, create app demonstrations, and understand your view hierarchy.

## Touch Visualizer

Display visual indicators for touch events - perfect for screen recordings and demos.

### Enabling Touch Visualization

```swift
// Via the interface facade
Scyther.interface.touchVisualizerEnabled = true

// Or directly
InterfaceToolkit.instance.visualiseTouches = true
```

### Configuration Options

Customize the touch indicator appearance:

```swift
var config = TouchVisualiserConfiguration()

// Show how long each touch has been active
config.showsTouchDuration = true

// Scale indicator based on touch pressure/radius
config.showsTouchRadius = true

// Log touch events to console
config.loggingEnabled = true

// Custom indicator color
config.touchIndicatorColor = .systemBlue

// Apply configuration
TouchVisualiser.instance.config = config
```

### Use Cases

- **App Demos**: Show users exactly where to tap
- **Bug Reports**: Record touch interactions for developers
- **Tutorials**: Create visual guides for your app
- **Accessibility Testing**: Verify touch targets are properly sized

## Grid Overlay

Display an alignment grid over your UI to verify spacing and alignment.

### Enabling the Grid

```swift
// Enable grid overlay
Scyther.interface.gridOverlayEnabled = true
```

### Customization

```swift
// Set grid size (spacing between lines)
GridOverlay.instance.size = 8  // 8-point grid

// Adjust opacity
GridOverlay.instance.opacity = 0.5

// Change color scheme
GridOverlay.instance.colorScheme = .blue
```

### Design System Verification

Use the grid overlay to verify your app follows your design system's spacing rules:

```swift
// For an 8-point grid system
GridOverlay.instance.size = 8

// For a 4-point grid system
GridOverlay.instance.size = 4
```

## View Frame Debugging

Highlight view boundaries to understand your view hierarchy.

### Show View Frames

Toggle colored borders around all views:

```swift
InterfaceToolkit.showViewFrames = true
```

Each view gets a randomly colored border, making it easy to see view boundaries and identify overlapping or misaligned views.

### Show View Sizes

Display dimension labels on views:

```swift
InterfaceToolkit.showViewSizes = true
```

This shows width and height labels, helping you verify views are sized correctly.

## Slow Animations

Reduce animation speed to debug timing issues:

```swift
InterfaceToolkit.slowAnimationsEnabled = true
```

Animations run at 10% speed, making it easier to:
- Debug animation glitches
- Verify animation sequences
- Test interruptible animations
- Identify janky transitions

## Font Browser

Explore all available system fonts. Access via **Fonts** in the Scyther menu to:

- Browse all font families
- See all weights and styles
- Preview fonts at different sizes
- Copy font names for use in code

## Interface Previews

Register UI components for quick preview access:

```swift
// Register a view for preview
Scyther.register(preview: MyCustomButton.self, name: "Custom Button")
Scyther.register(preview: ProfileCard.self, name: "Profile Card")
```

Access registered previews in the Scyther menu under **Interface Previews**.

## Programmatic Access

All UI tools are accessible programmatically:

```swift
// Touch visualization
Scyther.interface.touchVisualizerEnabled = true/false

// Grid overlay
Scyther.interface.gridOverlayEnabled = true/false

// View debugging
InterfaceToolkit.showViewFrames = true/false
InterfaceToolkit.showViewSizes = true/false
InterfaceToolkit.slowAnimationsEnabled = true/false
```

## Best Practices

### 1. Use for Screenshots

Enable the grid overlay when taking design review screenshots to verify alignment.

### 2. Demo Recordings

Enable touch visualization before recording app demos or tutorials.

### 3. Layout Debugging Workflow

When debugging layout issues:
1. Enable **Show View Frames** to see boundaries
2. Enable **Show View Sizes** to verify dimensions
3. Enable **Grid Overlay** to check alignment
4. Use **Slow Animations** if the issue involves animation

### 4. Disable in Production

All UI debugging tools are automatically disabled in App Store builds.

## See Also

- ``InterfaceToolkit``
- ``TouchVisualiser``
- ``TouchVisualiserConfiguration``
- ``GridOverlay``

