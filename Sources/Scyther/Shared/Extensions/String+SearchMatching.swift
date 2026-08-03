//
//  String+SearchMatching.swift
//  Scyther
//
//  Created by Brandon Stillitano on 3/8/2026.
//

import Foundation

extension String {
    /// Whether the string matches a search query the way Scyther's browser screens
    /// expect: case- and diacritic-insensitively, and treating underscores as spaces
    /// on both sides — so "base url" finds `API_BASE_URL` and "auth token" finds
    /// `auth_token`.
    ///
    /// - Parameter query: The user's trimmed search text.
    /// - Returns: `true` when the string contains the query under those rules.
    func searchMatches(_ query: String) -> Bool {
        func despaced(_ string: String) -> String {
            string.replacingOccurrences(of: "_", with: " ")
        }
        return localizedStandardContains(query)
            || despaced(self).localizedStandardContains(despaced(query))
    }
}
