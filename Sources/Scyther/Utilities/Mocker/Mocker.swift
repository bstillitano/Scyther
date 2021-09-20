//
//  File.swift
//
//
//  Created by Brandon Stillitano on 20/9/21.
//

import Foundation

internal enum Mocker {
    static var nestedDictionaryData: [String: [String: Any]] {
        return [
            "DictionaryData": [
                "String": "Stringy",
                "Int": 1,
                "Bool": true,
                "StringArray": ["String1", "String2", "String3"],
                "MixedArray": ["String", 1, true]
            ]
        ]
    }
}
