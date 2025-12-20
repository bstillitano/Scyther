//
//  CookieDetailsView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

struct CookieDetailsView: View {
    let cookie: HTTPCookie

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CookieDetailsViewModel

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

struct CookieDetailItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

class CookieDetailsViewModel: ViewModel {
    private let cookie: HTTPCookie

    @Published var keyValues: [CookieDetailItem] = []
    @Published var properties: [CookieDetailItem] = []

    init(cookie: HTTPCookie) {
        self.cookie = cookie
        super.init()
    }

    override func onFirstAppear() async {
        await super.onFirstAppear()
        await prepareObjects()
    }

    @MainActor
    private func prepareObjects() async {
        keyValues = [
            CookieDetailItem(key: "Name", value: cookie.name),
            CookieDetailItem(key: "Value", value: cookie.value.isEmpty ? "-" : cookie.value),
            CookieDetailItem(key: "Path", value: cookie.path),
            CookieDetailItem(key: "Domain", value: cookie.domain),
            CookieDetailItem(key: "Comment", value: cookie.comment ?? "-"),
            CookieDetailItem(key: "Comment URL", value: cookie.commentURL?.absoluteString ?? "-"),
            CookieDetailItem(key: "Expires", value: cookie.expiresDate?.formatted() ?? "-"),
            CookieDetailItem(key: "HTTP Only", value: cookie.isHTTPOnly ? "Yes" : "No"),
            CookieDetailItem(key: "HTTPS Only", value: cookie.isSecure ? "Yes" : "No"),
            CookieDetailItem(key: "Session Only", value: cookie.isSessionOnly ? "Yes" : "No"),
            CookieDetailItem(key: "Ports", value: cookie.portList?.map { "\($0)" }.joined(separator: ", ") ?? "-"),
            CookieDetailItem(key: "Version", value: "\(cookie.version)")
        ]

        properties = (cookie.properties ?? [:]).map { key, value in
            CookieDetailItem(key: key.rawValue, value: "\(value)")
        }.sorted { $0.key < $1.key }
    }

    @MainActor
    func deleteCookie() {
        HTTPCookieStorage.shared.deleteCookie(cookie)
        UserDefaults.standard.synchronize()
    }
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
