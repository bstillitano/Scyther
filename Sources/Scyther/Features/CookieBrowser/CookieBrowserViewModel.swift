//
//  CookieBrowserViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model for the cookie browser view.
///
/// `CookieBrowserViewModel` manages the loading, deleting, and clearing of HTTP cookies
/// from `HTTPCookieStorage`. It provides a reactive list of cookies that automatically
/// updates when cookies are added or removed.
///
/// ## Features
///
/// - Loads all cookies from `HTTPCookieStorage` on first appearance
/// - Sorts cookies alphabetically by name for easy browsing
/// - Supports deleting individual cookies
/// - Supports clearing all cookies at once
/// - Publishes changes via `@Published` properties for SwiftUI binding
///
/// ## Usage
///
/// The view model is typically used with `CookieBrowserView`:
///
/// ```swift
/// struct CookieBrowserView: View {
///     @StateObject private var viewModel = CookieBrowserViewModel()
///
///     var body: some View {
///         List {
///             ForEach(viewModel.cookies) { cookie in
///                 Text(cookie.name)
///             }
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Loading Cookies
///
/// - ``onFirstAppear()``
///
/// ### Managing Cookies
///
/// - ``cookies``
/// - ``deleteCookie(_:)``
/// - ``clearAllCookies()``
@MainActor
class CookieBrowserViewModel: ViewModel {
    /// All cookies currently displayed in the browser.
    ///
    /// This array contains `CookieItem` objects representing all cookies from
    /// `HTTPCookieStorage`, sorted alphabetically by name. The array is updated
    /// when cookies are loaded, deleted, or cleared.
    @Published var cookies: [CookieItem] = []

    /// Called when the view appears for the first time.
    ///
    /// This method loads all cookies from `HTTPCookieStorage` and populates
    /// the `cookies` array.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadCookies()
    }

    /// Loads all cookies from storage and sorts them by name.
    ///
    /// This method fetches all cookies from `CookieBrowser.instance`, converts them
    /// to `CookieItem` objects, and sorts them alphabetically by name.
    private func loadCookies() async {
        cookies = CookieBrowser.instance.cookies.map { cookie in
            CookieItem(name: cookie.name, domain: cookie.domain, cookie: cookie)
        }.sorted { $0.name < $1.name }
    }

    /// Deletes a specific cookie from storage and removes it from the list.
    ///
    /// This method removes the cookie from both `HTTPCookieStorage` and the
    /// local `cookies` array.
    ///
    /// - Parameter item: The cookie item to delete.
    func deleteCookie(_ item: CookieItem) {
        HTTPCookieStorage.shared.deleteCookie(item.cookie)
        cookies.removeAll { $0.id == item.id }
    }

    /// Deletes all cookies from storage and clears the list.
    ///
    /// This method iterates through all cookies and removes them from
    /// `HTTPCookieStorage`, then clears the local `cookies` array.
    func clearAllCookies() {
        for cookie in CookieBrowser.instance.cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        cookies.removeAll()
    }
}
