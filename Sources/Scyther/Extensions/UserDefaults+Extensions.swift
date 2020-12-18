//
//  File.swift
//
//
//  Created by Brandon Stillitano on 18/12/20.
//

import Foundation

internal extension UserDefaults {
    var stringStringDictionaryRepresentation: [String: String] {
        var dictionary: [String: String] = [:]
        for keyValuePair in dictionaryRepresentation() {
            /// Setup Data
            var value: String?

            /// Check Value Type
            switch keyValuePair.value {
            case is String:
                value = keyValuePair.value as? String

            case is Bool:
                value = (keyValuePair.value as? Bool)?.stringValue

            case is Array<Any>:
                value = "\((keyValuePair.value as? Array<Any>)?.count ?? 0) elements"
            default:
                break
            }

            /// Set K/V Data
            dictionary[keyValuePair.key] = value
        }
        return dictionary
    }
}
