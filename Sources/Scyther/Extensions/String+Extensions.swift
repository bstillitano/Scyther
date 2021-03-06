//
//  String+Extension.swift
//  MYTUtilityKit
//
//  Created by Brandon Stillitano on 4/12/20.
//

#if !os(macOS)
import UIKit

public extension String {
    /**
     Replaces all occurences of an array of strings with the provided replacement string.
     
     - Parameters:
        - characters: The group of characters values that are to be resolved.
        - replacement: The character that is to be used as the replacement for the given character set.
     
     - Returns: A string value that contains all the occurences of a character set with another character.
     
     - Complexity: O(*n*) where *n* is the number of strings in the `characters` array.
     */
    func replacingOccurences(of characters: [String], with replacement: String) -> String {
        //Setup Data
        var newValue: String = self

        //Itterate Characters
        characters.forEach { string in
            newValue = newValue.replacingOccurrences(of: string, with: replacement)
        }

        return newValue
    }

    /**
     The current app version for the running application.
     */
    static var appVersion: String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /**
     The current build number for the running application.
     */
    static var buildNumber: String? {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}
#endif
