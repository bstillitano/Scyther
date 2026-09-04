//
//  CookieBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A SwiftUI view for browsing and managing HTTP cookies.
///
/// This view displays all cookies stored in `HTTPCookieStorage` with the ability to:
/// - Search by cookie name, domain, or value
/// - View detailed information about each cookie
/// - Delete individual cookies via swipe actions
/// - Clear all cookies at once with confirmation
///
/// Each cookie row shows its name and domain, and tapping a cookie navigates to
/// its detailed view where all properties can be inspected.
struct CookieBrowserView: View {
    @StateObject private var viewModel = CookieBrowserViewModel()
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            Section(localized("HTTPCookieStorage Cookies")) {
                if viewModel.cookies.isEmpty {
                    Text(localized("No HTTP Cookies"))
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if viewModel.filteredCookies.isEmpty {
                    noSearchResults
                } else {
                    ForEach(viewModel.filteredCookies) { cookie in
                        NavigationLink {
                            CookieDetailsView(cookie: cookie.cookie)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cookie.name)
                                Text(cookie.domain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteCookie(cookie)
                            } label: {
                                Label(localized("Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !viewModel.cookies.isEmpty {
                Section {
                    Button(localized("Clear all cookies"), role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: localized("Search names, domains and values"))
        .navigationTitle(localized("Cookie Browser"))
        .alert(
            localized("Clear the entire cookie store?"),
            isPresented: $showingClearConfirmation
        ) {
            Button(localized("Clear All"), role: .destructive) {
                viewModel.clearAllCookies()
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("This action cannot be undone."))
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    /// Shown when a search query matches no cookies.
    @ViewBuilder
    private var noSearchResults: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            Text(localized("No results for \"\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\""))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// A view model item representing a single cookie in the list.
struct CookieItem: Identifiable {
    /// Unique identifier for this cookie item.
    let id = UUID()

    /// The name of the cookie.
    let name: String

    /// The domain the cookie belongs to.
    let domain: String

    /// The underlying HTTP cookie object.
    let cookie: HTTPCookie
}

#Preview {
    NavigationStack {
        CookieBrowserView()
    }
}
