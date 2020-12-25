//
//  UIDevice+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/12/20.
//

#if !os(macOS)
import UIKit

public extension UIDevice {
    /// Determines the machine identifier for the running device. - https://gist.github.com/adamawolf/3048717
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

    /// Determines the type of device that this code is running on. Returns one of the following: `phone` or `tablet`
    var deviceType: String {
        //Check Type
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "tablet"
        }

        return "phone"
    }

    /// Determines the generation of the running device.
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
    
    /// Gets a `URL` for an icon file that represents the current running device
    var deviceIconURL: URL? {
        return MobileDevices.instance?.iconURL
    }
}
#endif
