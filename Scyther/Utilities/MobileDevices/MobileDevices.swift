//
//  MobileDevices.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/12/20.
//

#if !os(macOS)
import UIKit

class MobileDevices {

    static let instance = MobileDevices()

    private let devices: [MobileDevice]
    private var bestMatchForCurrentDevice: MobileDevice?

    // MARK: - Init
    private init?() {
        // Parse base64 data from below into a `Data` object
        guard let data = Data(base64Encoded: MobileDevices.plistData) else {
            print("RETURN NIL")
            print("-----------")
            print(MobileDevices.plistData)
            return nil
        }

        // We need to be able to transform this data into a Plist
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }

        // Map exported type declartions into memory
        let exportedTypeDeclarations = plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []

        devices = exportedTypeDeclarations.compactMap { MobileDevice(from: $0) }
    }

    // MARK: - Helper functions

    func findBestMatchForCurrentDevice() -> MobileDevice? {
        // Aquire hardware model & color from MobileGestalt
        let hardwareModel: String? = UIDevice.current.model // HWModelStr
        let hardwareColor: String? = "1" // DeviceEnclosureColor

        guard let model = hardwareModel else { return nil }
        let matchingDevices = devices.filter { $0.equivalentTypes.contains(model) }

        // If we only have 1 device or hardware coor is unknown, return first value
        if matchingDevices.count == 1 || (matchingDevices.count > 1 && hardwareColor == nil) {
            return matchingDevices.first
        }

        // Try find a better match that contains the device color code
        if let color = hardwareColor {
            let colorMatchingDevices = matchingDevices.filter { $0.identifier.hasSuffix("-\(color))") }

            // If we have a match, first the first item, otherwise; default back to the first
            // item from the original array of matching devices
            return colorMatchingDevices.first ?? matchingDevices.first
        }

        return nil
    }


    // MARK: - Properties

    private var device: MobileDevice? {
        #if targetEnvironment(simulator)
            self.bestMatchForCurrentDevice = .iOSSimulator
        #endif

        if let device = bestMatchForCurrentDevice {
            return device
        } else {
            // Attempt to find the best match for the current device, This is also used as a partial
            // caching mechinism
            self.bestMatchForCurrentDevice = findBestMatchForCurrentDevice()

            return bestMatchForCurrentDevice
        }
    }

    /// Device identifier
    var identifier: String? { device?.identifier }

    /// Device description
    var description: String? { device?.description }

    /// Device icon file name
    var iconFileName: String? { device?.iconFileName }

    /// Device remote icon URL
    var iconURL: URL? {
        guard let fileName = iconFileName else { return nil }
        return URL(string: "https://github.com/Yoshimi-Robotics/MobileDevices/raw/master/Resources/\(fileName)")
    }

    /// Device equivalent types
    var equivalentTypes: [String]? { device?.equivalentTypes }
}

struct MobileDevice {

    let identifier: String
    let description: String?
    let iconFileName: String?
    let equivalentTypes: [String]

    // MARK: - Init

    init?(from dict: [String: Any]) {
        // We require an identifier at minimum
        guard let identifier = dict["UTTypeIdentifier"] as? String else {
            print("Unable to find a `UTTypeIdentifier` in \(dict)")
            return nil
        }

        self.identifier = identifier
        self.description = dict["UTTypeDescription"] as? String
        self.iconFileName = dict["UTTypeIconFile"] as? String

        if let tags = dict["UTTypeTagSpecification"] as? [String: Any] {
            self.equivalentTypes = tags["com.apple.device-model-code"] as? [String] ?? []
        } else {
            self.equivalentTypes = []
        }
    }

    private init(identifier: String, description: String?, iconFileName: String?, equivalentTypes: [String]) {
        self.identifier = identifier
        self.description = description
        self.iconFileName = iconFileName
        self.equivalentTypes = equivalentTypes
    }

    // MARK: - Helper accessors

    static var iOSSimulator: MobileDevice {
        MobileDevice(identifier: "com.apple.ios.simulator", description: "iOS Simulator", iconFileName: "com.apple.ios.simulator.icns", equivalentTypes: [])
    }

}
#endif

extension MobileDevices {
    internal static var plistData: String {
        /// Get Bundle of Scyther as opposed to Bundle of client running the library.
        let bundle = Bundle(for: self)
        
        /// Get file path and return contents of file
        guard let path = bundle.path(forResource: "MobileDevicesPlist", ofType: "txt") else {
            return ""
        }
        print(try? String(contentsOfFile: path))
        return (try? String(contentsOfFile: path)) ?? ""
    }
}
