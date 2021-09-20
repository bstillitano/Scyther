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
            ],
            "JSON Data": [
                "JSON String": Self.jsonString
            ]
        ]
    }
    
    static var jsonString: String {
        """
        {
            "glossary": {
                "title": "example glossary",
                "GlossDiv": {
                    "title": "S",
                    "GlossList": {
                        "GlossEntry": {
                            "ID": "SGML",
                            "SortAs": "SGML",
                            "GlossTerm": "Standard Generalized Markup Language",
                            "Acronym": "SGML",
                            "Abbrev": "ISO 8879:1986",
                            "GlossDef": {
                                "para": "A meta-markup language, used to create markup languages such as DocBook.",
                                "GlossSeeAlso": ["GML", "XML"]
                            },
                            "GlossSee": "markup"
                        }
                    }
                }
            }
        }
        """
    }
}
