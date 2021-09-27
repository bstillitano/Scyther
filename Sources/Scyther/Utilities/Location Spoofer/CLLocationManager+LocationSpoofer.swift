//
//  File.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import CoreLocation
import Foundation

// MARK: - Swizzle Event Location
internal extension CLLocationManager {
    static let swizzle: Void = {
        swizzleEventLocation
        swizzleEventLocationForceMappingMatchType
    }()
    
    static let swizzleEventLocation: Void = {
        let selectorString: String = String(data: Data(bytes: [0x6f, 0x6e, 0x43, 0x6c, 0x69, 0x65, 0x6e, 0x74, 0x45, 0x76, 0x65, 0x6e, 0x74, 0x4c, 0x6f, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x3a],
                                                       count: 22),
                                            encoding: .ascii) ?? ""
        guard let originalMethod = class_getInstanceMethod(CLLocationManager.self,
                                                           Selector(selectorString)) else {
            return
        }
        guard let swizzledMethod = class_getInstanceMethod(CLLocationManager.self,
                                                           #selector(scyther_onClientEventLocationSelector(dictionary:))) else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    static let swizzleEventLocationForceMappingMatchType: Void = {
        let selectorString: String = String(data: Data(bytes: [0x6f, 0x6e, 0x43, 0x6c, 0x69, 0x65, 0x6e, 0x74, 0x45, 0x76, 0x65, 0x6e, 0x74, 0x4c, 0x6f, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x3a, 0x66, 0x6f, 0x72, 0x63, 0x65, 0x4d, 0x61, 0x70, 0x4d, 0x61, 0x74, 0x63, 0x68, 0x69, 0x6e, 0x67, 0x3a, 0x74, 0x79, 0x70, 0x65, 0x3a],
                                                       count: 44),
                                            encoding: .ascii) ?? ""
        guard let originalMethod = class_getInstanceMethod(CLLocationManager.self,
                                                           Selector(selectorString)) else {
            return
        }
        guard let swizzledMethod = class_getInstanceMethod(CLLocationManager.self,
                                                           #selector(scyther_onClientEventLocationSelector(dictionary:forceMapMatching:type:))) else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    /// Swizzled implementation of `onClientEventLocation`
    @objc
    private func scyther_onClientEventLocationSelector(dictionary: NSDictionary) {
        guard let location: CLLocation = LocationSpoofer.instance.simulatedLocation else {
            scyther_onClientEventLocationSelector(dictionary: dictionary)
            return
        }
        delegate?.locationManager?(self, didUpdateLocations: [location])
    }

    /// Swizzled implementation of `onClientEventLocation:forceMapMatching:type`
    @objc
    private func scyther_onClientEventLocationSelector(dictionary: NSDictionary, forceMapMatching: Bool, type: Any) {
        guard let location: CLLocation = LocationSpoofer.instance.simulatedLocation else {
            scyther_onClientEventLocationSelector(dictionary: dictionary, forceMapMatching: forceMapMatching, type: type)
            return
        }
        delegate?.locationManager?(self, didUpdateLocations: [location])
    }
}
