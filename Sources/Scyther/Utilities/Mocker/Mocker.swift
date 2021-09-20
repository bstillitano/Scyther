//
//  File.swift
//
//
//  Created by Brandon Stillitano on 20/9/21.
//

import Foundation

internal enum Mocker {
    static var nestedDictionaryData: [String: [String: Any]] {
        let basicDictionary: [String: Any] = [
            "DictionaryString": "String",
            "DictionaryInt": 1,
            "DictionaryBool": true
        ]
        return [
            "Dictionary Data": [
                "String": "Stringy",
                "Int": 69,
                "Bool": true,
                "String Array": ["String1", "String2", "String3"],
                "Dictionary Array": [basicDictionary, basicDictionary],
                "Nested Dictionary": [
                    "String": "Stringy",
                    "Int": 420,
                    "Bool": true,
                    "StringArray": ["String1", "String2", "String3"],
                ]
            ]
        ]
    }
}
