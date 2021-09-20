//
//  File.swift
//
//
//  Created by Brandon Stillitano on 20/9/21.
//

import Foundation

extension NSDictionary {
    var swiftDictionary: Dictionary<String, Any> {
        var swiftDictionary = Dictionary<String, Any>()

        for key: Any in self.allKeys {
            guard let stringKey = key as? String else {
                continue
            }
            if let keyValue = self.value(forKey: stringKey) {
                swiftDictionary[stringKey] = keyValue
            }
        }

        return swiftDictionary
    }
}
