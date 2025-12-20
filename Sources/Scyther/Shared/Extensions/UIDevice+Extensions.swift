//
//  UIDevice+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/12/20.
//

#if !os(macOS)
import UIKit

/// Provides convenient extensions for device identification and metadata.
///
/// This extension adds utility properties to retrieve detailed information about the
/// running device, including its model identifier, device type, and generation.
public extension UIDevice {
    /// Returns the machine identifier for the running device.
    ///
    /// This property uses the `uname` system call to retrieve the device's internal
    /// model identifier (e.g., "iPhone14,5" for iPhone 13, "iPad13,1" for iPad Air 4th gen).
    /// This identifier is more specific than the generic model names provided by UIDevice.
    ///
    /// - Returns: A string containing the device's machine identifier (e.g., "iPhone14,5")
    ///
    /// ## Example
    /// ```swift
    /// let identifier = UIDevice.current.modelName
    /// print(identifier) // e.g., "iPhone14,5" or "x86_64" (simulator)
    /// ```
    ///
    /// - Note: On simulators, this will return architecture identifiers like "x86_64" or "arm64".
    ///
    /// - SeeAlso: [Complete list of iOS device identifiers](https://gist.github.com/adamawolf/3048717)
    var modelName: String {
        /// Get System Info
        var systemInfo = utsname()
        uname(&systemInfo)

        /// Determine Device Identifier
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else {
                return identifier
            }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        return identifier
    }

    /// Determines the general type of device.
    ///
    /// Returns a simplified categorization of the device as either a phone or tablet
    /// based on the user interface idiom.
    ///
    /// - Returns: A string containing either `"phone"` or `"tablet"`
    ///
    /// ## Example
    /// ```swift
    /// let type = UIDevice.current.deviceType
    /// if type == "tablet" {
    ///     // Show iPad-optimized layout
    /// } else {
    ///     // Show iPhone-optimized layout
    /// }
    /// ```
    var deviceType: String {
        //Check Type
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "tablet"
        }

        return "phone"
    }

    /// Calculates the estimated generation year of the device.
    ///
    /// This property attempts to derive the device's generation year by parsing the model
    /// identifier and adding 2007 (the year the first iPhone was released). The calculation
    /// extracts numeric components from the model identifier and interprets them as an offset
    /// from 2007.
    ///
    /// - Returns: A float representing the estimated year of the device generation
    ///
    /// ## Example
    /// ```swift
    /// let year = UIDevice.current.generation
    /// print("Device generation: \(year)") // e.g., 2020.0 for iPhone 12
    /// ```
    ///
    /// - Note: This is an estimation and may not be 100% accurate for all device models.
    ///         Simulator devices return 2106.9 (99.9 + 2007).
    ///
    /// - Important: The calculation converts model identifiers like "iPhone13,2" to 13.2,
    ///              then adds 2007, resulting in 2020.2. This is a heuristic and should
    ///              not be relied upon for precise year calculations.
    var generation: Float {
        /// Setup Data
        var value: String = UIDevice.current.modelName
        value = value.lowercased()
        value = value.replacingOccurences(of: ["iphone", "ipad", "ipod", "watch"], with: "")
        value = value.replacingOccurences(of: ["x86_64", "i386"], with: "99.9")
        value = value.replacingOccurrences(of: ",", with: ".")

        /// Add 2007 to the value as that was the year of release for the first generation of iOS
        return (Float(value) ?? 0) + 2007
    }
}
#endif
