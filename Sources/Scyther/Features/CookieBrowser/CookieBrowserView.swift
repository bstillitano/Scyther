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
            Section("HTTPCookieStorage Cookies") {
                if viewModel.cookies.isEmpty {
                    Text("No HTTP Cookies")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.cookies) { cookie in
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
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !viewModel.cookies.isEmpty {
                Section {
                    Button("Clear all cookies", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Cookie Browser")
        .confirmationDialog(
            "Clear all cookies?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                viewModel.clearAllCookies()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
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
