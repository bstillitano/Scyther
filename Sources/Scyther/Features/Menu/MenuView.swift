//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import SwiftUI

public struct MenuView: View {
    @StateObject private var viewModel: NewMenuViewModel = NewMenuViewModel()

    public init() {}

    public var body: some View {
        List {
            Section {
                header
                row(
                    withLabel: "OS Version",
                    description: UIDevice.current.systemVersion
                )
                row(
                    withLabel: "Hardware",
                    description: UIDevice.current.modelName
                )
                row(
                    withLabel: "Release Year",
                    description: UIDevice.current.generation.withoutDecimals
                )
                row(
                    withLabel: "UUID",
                    description: UIDevice.current.identifierForVendor?.uuidString
                )
            } header: {
                Text("Device")
            }
            
            Section {
                row(
                    withLabel: "App ID Prefix",
                    description: Bundle.main.seedId
                )
                row(
                    withLabel: "Display Name",
                    description: String(UIApplication.shared.appName)
                )
                row(
                    withLabel: "Bundle ID",
                    description: Bundle.main.bundleIdentifier
                )
                row(
                    withLabel: "Process ID",
                    description: String(getpid())
                )
                row(
                    withLabel: "Version",
                    description: Bundle.main.versionNumber
                )
                row(
                    withLabel: "Build Number",
                    description: Bundle.main.buildNumber
                )
                row(
                    withLabel: "Build Date",
                    description: Bundle.main.buildDate.formatted()
                )
                row(
                    withLabel: "Release Type",
                    description: AppEnvironment.configuration().rawValue
                )
            } header: {
                Text("Application")
            }
            
            Section {
                row(
                    withLabel: "IP Address",
                    description: viewModel.ipAddress,
                    icon: "network",
                    andLoadingState: viewModel.isLoadingIPAddress
                )
                NavigationLink {
                    NetworkLogsView()
                } label: {
                    row(
                        withLabel: "Network Logs",
                        icon: "text.page.badge.magnifyingglass"
                    )
                }
                NavigationLink {
                    ServerConfigurationView()
                } label: {
                    row(
                        withLabel: "Server Configuration",
                        icon: "server.rack"
                    )
                }
                NavigationLink {
                    EnvironmentVariablesView()
                } label: {
                    row(
                        withLabel: "Environment Variables",
                        icon: "x.squareroot"
                    )
                }
            } header: {
                Text("Networking")
            }
            
            Section {
                NavigationLink {
                    FeatureFlagsView()
                } label: {
                    row(withLabel: "Feature Flags", icon: "flag")
                }
                NavigationLink {
                    UserDefaultsView()
                } label: {
                    row(withLabel: "UserDefaults", icon: "face.dashed")
                }
                NavigationLink {
                    CookieBrowserView()
                } label: {
                    row(withLabel: "Cookies", icon: "info.circle")
                }
            } header: {
                Text("Data")
            }
            
            Section {
                NavigationLink {
                    KeychainBrowserView()
                } label: {
                    row(withLabel: "Keychain Browser", icon: "key")
                }
            } header: {
                Text("Security")
            }
            
            Section {
                NavigationLink {
                    LocationSpooferView()
                } label: {
                    row(withLabel: "Location Spoofer", icon: "location.circle")
                }
            } header: {
                Text("System Tools")
            }
            
            Section {
                NavigationLink {
                    NotificationLoggerView()
                } label: {
                    row(withLabel: "Notification Logger", icon: "list.bullet")
                }
                NavigationLink {
                    NotificationTesterView()
                } label: {
                    row(withLabel: "Notification Tester", icon: "bell")
                }
                row(withLabel: "APNS Token", icon: "applelogo")
                row(withLabel: "FCM Token", icon: "flame")
            } header: {
                Text("Notifications")
            }
            
            Section {
                NavigationLink {
                    FontsView()
                } label: {
                    row(withLabel: "Fonts", icon: "textformat")
                }
                NavigationLink {
                    InterfacePreviewsView()
                } label: {
                    row(withLabel: "Interface Components", icon: "apps.iphone")
                }
                NavigationLink {
                    GridOverlaySettingsView()
                } label: {
                    row(withLabel: "Grid Overlay", icon: "rectangle.split.3x3")
                }
                NavigationLink {
                    TouchVisualiserView()
                } label: {
                    row(withLabel: "Touch Visualiser", icon: "hand.point.up")
                }
            } header: {
                Text("UI/UX")
            }
            
            Section {
                NavigationLink {
                    ConsoleLoggerView()
                } label: {
                    row(withLabel: "Console Logs", icon: "terminal")
                }
            } header: {
                Text("Development Tools")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Scyther.hideMenu()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .navigationTitle("Scyther")
        .interactiveDismissDisabled()
    }
    
    func row(withLabel label: String, description: String? = nil, icon: String? = nil, andLoadingState loading: Bool = false) -> some View {
        HStack {
            if let icon {
                Label(label, systemImage: icon)
            } else {
                Text(label)
            }
            if loading {
                ProgressView()
            } else if let description {
                Text(description)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    
    var header: some View {
        HStack(spacing: 16) {
            if let image = UIImage.appIcon {
                Image(uiImage: image)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray, lineWidth: 1)
                    )
            }
            VStack(alignment: .leading) {
                Text(UIDevice.current.name)
                Text(UIDevice.current.model)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

class NewMenuViewModel: ViewModel {
    @Published var ipAddress: String = ""
    @Published var isLoadingIPAddress: Bool = true
    
    override func onFirstAppear() async {
        await super.onFirstAppear()
    
        await loadIPAddress()
    }
    
    @MainActor private func loadIPAddress() async {
        defer { isLoadingIPAddress = false }
        isLoadingIPAddress = true
        ipAddress = await NetworkHelper.instance.ipAddress
    }
}

class ViewModel: ObservableObject {
    init() {
        setup()
    }

    func setup() {
        
    }
    
    func onFirstAppear() async {
        
    }
    
    func onAppear() async {
        
    }
    
    func onSubsequentAppear() async {
        
    }
}
