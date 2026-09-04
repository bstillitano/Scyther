//
//  CookieDetailsViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import Foundation
import SwiftUI

/// View model for the cookie details view.
///
/// `CookieDetailsViewModel` extracts and formats all properties from an HTTP cookie
/// for display in a structured list view. It separates standard key-value pairs
/// (name, domain, path, etc.) from additional cookie properties.
///
/// ## Features
///
/// - Extracts standard cookie properties (name, value, domain, path, expiration, etc.)
/// - Formats boolean properties as human-readable "Yes/No" values
/// - Handles optional properties gracefully with "-" placeholders
/// - Separates standard key-values from additional cookie properties
/// - Supports deleting the cookie from storage
/// - Publishes changes via `@Published` properties for SwiftUI binding
///
/// ## Usage
///
/// The view model is typically used with `CookieDetailsView`:
///
/// ```swift
/// struct CookieDetailsView: View {
///     let cookie: HTTPCookie
///     @StateObject private var viewModel: CookieDetailsViewModel
///
///     init(cookie: HTTPCookie) {
///         self.cookie = cookie
///         _viewModel = StateObject(wrappedValue: CookieDetailsViewModel(cookie: cookie))
///     }
///
///     var body: some View {
///         List {
///             ForEach(viewModel.keyValues) { item in
///                 Text("\(item.key): \(item.value)")
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
/// ### Initialization
///
/// - ``init(cookie:)``
///
/// ### Cookie Properties
///
/// - ``keyValues``
/// - ``properties``
///
/// ### Lifecycle
///
/// - ``onFirstAppear()``
///
/// ### Actions
///
/// - ``deleteCookie()``
@MainActor
class CookieDetailsViewModel: ViewModel {
    /// The cookie being displayed.
    private let cookie: HTTPCookie

    /// Standard cookie key-value pairs (name, domain, path, etc.).
    ///
    /// This array contains the core cookie properties that are always present,
    /// such as name, value, domain, path, expiration date, and security flags.
    /// Values are formatted for display with placeholders for missing optional values.
    @Published var keyValues: [CookieDetailItem] = []

    /// Additional cookie properties from the properties dictionary.
    ///
    /// This array contains any additional properties from the cookie's `properties`
    /// dictionary that are not part of the standard key-values. Properties are
    /// sorted alphabetically by key.
    @Published var properties: [CookieDetailItem] = []

    /// Creates a cookie details view model.
    ///
    /// - Parameter cookie: The HTTP cookie to display details for.
    init(cookie: HTTPCookie) {
        self.cookie = cookie
        super.init()
    }

    /// Called when the view appears for the first time.
    ///
    /// This method prepares all cookie properties for display by extracting
    /// and formatting them into `CookieDetailItem` objects.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await prepareObjects()
    }

    /// Extracts and formats all cookie properties for display.
    ///
    /// This method separates cookie properties into two categories:
    /// - Standard key-values (name, value, domain, etc.)
    /// - Additional properties from the cookie's properties dictionary
    ///
    /// Properties are formatted for display with appropriate placeholders
    /// for missing optional values and human-readable representations
    /// for boolean flags.
    private func prepareObjects() async {
        keyValues = [
            CookieDetailItem(key: localized("Name"), value: cookie.name),
            CookieDetailItem(key: localized("Value"), value: cookie.value.isEmpty ? "-" : cookie.value),
            CookieDetailItem(key: localized("Path"), value: cookie.path),
            CookieDetailItem(key: localized("Domain"), value: cookie.domain),
            CookieDetailItem(key: localized("Comment"), value: cookie.comment ?? "-"),
            CookieDetailItem(key: localized("Comment URL"), value: cookie.commentURL?.absoluteString ?? "-"),
            CookieDetailItem(key: localized("Expires"), value: cookie.expiresDate?.formatted() ?? "-"),
            CookieDetailItem(key: localized("HTTP Only"), value: cookie.isHTTPOnly ? localized("Yes") : localized("No")),
            CookieDetailItem(key: localized("HTTPS Only"), value: cookie.isSecure ? localized("Yes") : localized("No")),
            CookieDetailItem(key: localized("Session Only"), value: cookie.isSessionOnly ? localized("Yes") : localized("No")),
            CookieDetailItem(key: localized("Ports"), value: cookie.portList?.map { "\($0)" }.joined(separator: ", ") ?? "-"),
            CookieDetailItem(key: localized("Version"), value: "\(cookie.version)")
        ]

        properties = (cookie.properties ?? [:]).map { key, value in
            CookieDetailItem(key: key.rawValue, value: "\(value)")
        }.sorted { $0.key < $1.key }
    }

    /// Deletes this cookie from storage.
    ///
    /// This method removes the cookie from `HTTPCookieStorage` and synchronizes
    /// `UserDefaults` to ensure the deletion is persisted.
    func deleteCookie() {
        HTTPCookieStorage.shared.deleteCookie(cookie)
        UserDefaults.standard.synchronize()
    }
}
