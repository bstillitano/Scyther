//
//  CookieDetailsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A SwiftUI view for displaying detailed information about an HTTP cookie.
///
/// This view shows all properties of a cookie including:
/// - Key/value pairs (name, value, domain, path, expiration, etc.)
/// - Cookie properties (HTTP-only, secure, session-only, etc.)
/// - Additional metadata
///
/// Each property can be copied to the clipboard via context menu. The view also
/// provides a toolbar button to delete the cookie.
struct CookieDetailsView: View {
    /// The HTTP cookie to display details for.
    let cookie: HTTPCookie

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CookieDetailsViewModel

    /// Creates a cookie details view for the specified cookie.
    ///
    /// - Parameter cookie: The HTTP cookie to display.
    init(cookie: HTTPCookie) {
        self.cookie = cookie
        _viewModel = StateObject(wrappedValue: CookieDetailsViewModel(cookie: cookie))
    }

    var body: some View {
        List {
            Section("Key/Values") {
                ForEach(viewModel.keyValues) { item in
                    row(for: item)
                }
            }

            Section("Properties") {
                if viewModel.properties.isEmpty {
                    Text("No cookie properties set")
                        .fontWeight(.bold)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.properties) { item in
                        row(for: item)
                    }
                }
            }
        }
        .navigationTitle("Cookie Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    viewModel.deleteCookie()
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    private func row(for item: CookieDetailItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.key)
            Text(item.value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = "\(item.key): \(item.value)"
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

/// A view model item representing a key-value pair in cookie details.
struct CookieDetailItem: Identifiable {
    /// Unique identifier for this detail item.
    let id = UUID()

    /// The key or property name.
    let key: String

    /// The value associated with the key.
    let value: String
}

#Preview {
    NavigationStack {
        if let cookie = HTTPCookie(properties: [
            .name: "session_id",
            .value: "abc123",
            .domain: "example.com",
            .path: "/"
        ]) {
            CookieDetailsView(cookie: cookie)
        }
    }
}
