//
//  ContentView.swift
//  ScytherExample
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI
import SwiftData
import Scyther

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
    @Environment(\.modelContext) private var modelContext
    @State private var requestCount = 0
    @State private var isLoading = false
    @State private var userCount = 0
    @State private var postCount = 0
    @State private var productCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Scyther Demo") {
                    Button("Open Scyther Menu") {
                        Scyther.showMenu()
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

                Section {
                    Button("Add More Records") {
                        addDemoRecords()
                    }

                    Button("Clear All Records", role: .destructive) {
                        clearDemoRecords()
                    }

                    LabeledContent("Users", value: "\(userCount)")
                    LabeledContent("Posts", value: "\(postCount)")
                    LabeledContent("Products", value: "\(productCount)")
                } header: {
                    Text("Database Demo")
                } footer: {
                    Text("Open Scyther → Data → Database Browser to browse the SwiftData database.")
                }

                #if DEBUG
                Section {
                    Button("Trigger Test Crash", role: .destructive) {
                        triggerTestCrash()
                    }
                } header: {
                    Text("Crash Testing")
                } footer: {
                    Text("This will crash the app. Reopen it to see the crash log in Scyther → System Tools → Crash Logs.")
                }
                #endif
            }
            .navigationTitle("Scyther Example")
            .onAppear {
                updateRecordCounts()
            }
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
        Scyther.featureFlags.register("new_onboarding_flow", remoteValue: true)
        Scyther.featureFlags.register("dark_mode_v2", remoteValue: false)
        Scyther.featureFlags.register("experimental_feature", remoteValue: false)
        Scyther.featureFlags.register("show_beta_badge", remoteValue: true)
        Scyther.featureFlags.register("enable_analytics", remoteValue: true)
        Scyther.featureFlags.register("use_new_api", remoteValue: false)
    }

    #if DEBUG
    private func triggerTestCrash() {
        Scyther.crashes.triggerTestCrash()
    }
    #endif

    // MARK: - Database Demo Functions

    private func updateRecordCounts() {
        userCount = (try? modelContext.fetchCount(FetchDescriptor<DemoUser>())) ?? 0
        postCount = (try? modelContext.fetchCount(FetchDescriptor<DemoPost>())) ?? 0
        productCount = (try? modelContext.fetchCount(FetchDescriptor<DemoProduct>())) ?? 0
    }

    private func addDemoRecords() {
        // Add a random user
        let randomUser = DemoUser(
            name: "User \(Int.random(in: 1000...9999))",
            email: "user\(Int.random(in: 1000...9999))@example.com",
            age: Int.random(in: 18...65)
        )
        modelContext.insert(randomUser)

        // Add a random post
        let randomPost = DemoPost(
            title: "Post \(Int.random(in: 1000...9999))",
            content: "This is a randomly generated post for testing purposes.",
            user: randomUser
        )
        modelContext.insert(randomPost)

        // Add a random product
        let categories = ["Electronics", "Audio", "Accessories", "Wearables", "Software"]
        let randomProduct = DemoProduct(
            name: "Product \(Int.random(in: 1000...9999))",
            price: Double.random(in: 9.99...999.99).rounded() / 100 * 100,
            inStock: Bool.random(),
            category: categories.randomElement() ?? "Other"
        )
        modelContext.insert(randomProduct)

        try? modelContext.save()
        updateRecordCounts()
    }

    private func clearDemoRecords() {
        do {
            try modelContext.delete(model: DemoUser.self)
            try modelContext.delete(model: DemoPost.self)
            try modelContext.delete(model: DemoProduct.self)
            try modelContext.save()
        } catch {
            print("Failed to clear demo records: \(error)")
        }
        updateRecordCounts()
    }
}

#Preview {
    ContentView()
}
