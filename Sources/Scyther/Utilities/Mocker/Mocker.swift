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
            "Dictionary Data": [
                "String": "Stringy",
                "Int": 1,
                "Bool": true,
                "String Array": ["String1", "String2", "String3"],
                "Dictionary Array": [
                    "DictionaryString": "String",
                    "DictionaryInt": 1,
                    "DictionaryBool": true
                ],
                "Nested Dictionary": [
                    "String": "Stringy",
                    "Int": 1,
                    "Bool": true,
                    "StringArray": ["String1", "String2", "String3"],
                ]
            ]
        ]
    }
}
