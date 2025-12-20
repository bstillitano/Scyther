//
//  CookieBrowser.swift
//  Scyther
//
//  Created by Brandon Stillitano on 19/2/21.
//

import Foundation

/// A singleton utility for accessing and managing HTTP cookies.
///
/// `CookieBrowser` provides a centralized interface to the shared `HTTPCookieStorage`,
/// allowing inspection and management of all cookies stored by the application.
///
/// ## Usage
/// ```swift
/// // Access all cookies
/// let allCookies = CookieBrowser.instance.cookies
///
/// // Iterate through cookies
/// for cookie in CookieBrowser.instance.cookies {
///     print("\(cookie.name): \(cookie.value)")
/// }
/// ```
class CookieBrowser {
    /// Private initializer to prevent external instantiation.
    private init() { }

    /// Shared singleton instance.
    public static let instance: CookieBrowser = CookieBrowser()

    /// All HTTP cookies currently stored in the shared cookie storage.
    ///
    /// This property accesses `HTTPCookieStorage.shared.cookies` and returns
    /// all cookies, or an empty array if none exist.
    ///
    /// - Returns: An array of all stored HTTP cookies.
    public var cookies: [HTTPCookie] {
        return HTTPCookieStorage.shared.cookies ?? []
    }
}
