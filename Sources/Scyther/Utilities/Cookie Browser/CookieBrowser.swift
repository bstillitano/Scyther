//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 19/2/21.
//

import Foundation

class CookieBrowser {
    /// Private init to stop re-initialisation
    private init() { }
    
    /// Singleton instance
    public static let instance: CookieBrowser = CookieBrowser()
    
    public var cookies: [HTTPCookie] {
        return HTTPCookieStorage.shared.cookies ?? []
    }
}
