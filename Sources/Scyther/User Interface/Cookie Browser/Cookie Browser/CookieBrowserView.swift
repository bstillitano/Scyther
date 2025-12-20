//
//  CookieBrowserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct CookieBrowserView: View {
    @StateObject private var viewModel = CookieBrowserSwiftUIViewModel()
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

struct CookieItem: Identifiable {
    let id = UUID()
    let name: String
    let domain: String
    let cookie: HTTPCookie
}

class CookieBrowserSwiftUIViewModel: ViewModel {
    @Published var cookies: [CookieItem] = []

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadCookies()
    }

    @MainActor
    private func loadCookies() async {
        cookies = CookieBrowser.instance.cookies.map { cookie in
            CookieItem(name: cookie.name, domain: cookie.domain, cookie: cookie)
        }.sorted { $0.name < $1.name }
    }

    @MainActor
    func deleteCookie(_ item: CookieItem) {
        HTTPCookieStorage.shared.deleteCookie(item.cookie)
        cookies.removeAll { $0.id == item.id }
    }

    @MainActor
    func clearAllCookies() {
        for cookie in CookieBrowser.instance.cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        cookies.removeAll()
    }
}

#Preview {
    NavigationStack {
        CookieBrowserView()
    }
}
