//
//  ContentView.swift
//  ScytherExample
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import Scyther

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            NavigationStack {
                LocationTestView()
            }
            .tabItem {
                Label("Location", systemImage: "location")
            }
        }
    }
}

struct HomeView: View {
    @State private var requestCount = 0
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Scyther Demo") {
                    Button("Open Scyther Menu") {
                        Scyther.presentMenu()
                    }

                    Button("Shake device to open menu") {}
                        .disabled(true)
                        .foregroundStyle(.secondary)
                }

                Section("Network Requests") {
                    Button {
                        makeNetworkRequest()
                    } label: {
                        HStack {
                            Text("Make Sample Request")
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading)

                    Button("Make Multiple Requests") {
                        makeMultipleRequests()
                    }
                    .disabled(isLoading)

                    LabeledContent("Requests Made", value: "\(requestCount)")
                }

                Section("User Defaults Demo") {
                    Button("Write Sample Data") {
                        writeSampleUserDefaults()
                    }

                    Button("Clear Sample Data") {
                        clearSampleUserDefaults()
                    }
                }

                Section("Feature Flags Demo") {
                    Button("Setup Sample Toggles") {
                        setupSampleToggles()
                    }
                }
            }
            .navigationTitle("Scyther Example")
        }
    }

    private func makeNetworkRequest() {
        isLoading = true
        Task {
            defer {
                Task { @MainActor in
                    isLoading = false
                    requestCount += 1
                }
            }

            let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
            let _ = try? await URLSession.shared.data(from: url)
        }
    }

    private func makeMultipleRequests() {
        isLoading = true
        Task {
            let urls = [
                "https://jsonplaceholder.typicode.com/posts/1",
                "https://jsonplaceholder.typicode.com/users/1",
                "https://jsonplaceholder.typicode.com/comments?postId=1",
                "https://jsonplaceholder.typicode.com/todos/1",
                "https://httpbin.org/get",
                "https://httpbin.org/json"
            ]

            for urlString in urls {
                if let url = URL(string: urlString) {
                    let _ = try? await URLSession.shared.data(from: url)
                    await MainActor.run {
                        requestCount += 1
                    }
                }
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func writeSampleUserDefaults() {
        UserDefaults.standard.set("John Doe", forKey: "example_username")
        UserDefaults.standard.set(42, forKey: "example_age")
        UserDefaults.standard.set(true, forKey: "example_premium_user")
        UserDefaults.standard.set(3.14159, forKey: "example_pi_value")
        UserDefaults.standard.set(["Swift", "iOS", "Scyther"], forKey: "example_tags")
        UserDefaults.standard.set([
            "name": "Test User",
            "email": "test@example.com",
            "settings": [
                "darkMode": true,
                "notifications": false
            ]
        ], forKey: "example_user_profile")
        UserDefaults.standard.set(Date(), forKey: "example_last_login")
    }

    private func clearSampleUserDefaults() {
        let keys = [
            "example_username",
            "example_age",
            "example_premium_user",
            "example_pi_value",
            "example_tags",
            "example_user_profile",
            "example_last_login"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func setupSampleToggles() {
        Scyther.toggler.configureToggle(withName: "new_onboarding_flow", remoteValue: true)
        Scyther.toggler.configureToggle(withName: "dark_mode_v2", remoteValue: false)
        Scyther.toggler.configureToggle(withName: "experimental_feature", remoteValue: false)
        Scyther.toggler.configureToggle(withName: "show_beta_badge", remoteValue: true)
        Scyther.toggler.configureToggle(withName: "enable_analytics", remoteValue: true)
        Scyther.toggler.configureToggle(withName: "use_new_api", remoteValue: false)
    }
}

#Preview {
    ContentView()
}
