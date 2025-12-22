//
//  MenuView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import SwiftUI

/// The main menu interface for the Scyther developer toolkit.
///
/// `MenuView` provides a comprehensive dashboard for accessing all Scyther features,
/// organized into logical sections:
/// - **Device**: Hardware and OS information
/// - **Application**: App metadata and build details
/// - **Networking**: Network tools, logs, and configuration
/// - **Data**: Feature flags, UserDefaults, cookies
/// - **Security**: Keychain browser
/// - **System Tools**: Location spoofer, console logs
/// - **Notifications**: Notification logger and tester
/// - **UI/UX**: Fonts, components, grid overlay, touch visualizer
/// - **Development Tools**: Custom developer options configured via ``Scyther/developerOptions``
///
/// The menu displays device information in a header and provides navigation
/// to all sub-features.
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
                NavigationLink {
                    FileBrowserView()
                } label: {
                    row(withLabel: "File Browser", icon: "folder")
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
                NavigationLink {
                    ConsoleLoggerView()
                } label: {
                    row(withLabel: "Console Logs", icon: "terminal")
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
                    FPSCounterSettingsView()
                } label: {
                    row(withLabel: "FPS Counter", icon: "speedometer")
                }
                NavigationLink {
                    TouchVisualiserView()
                } label: {
                    row(withLabel: "Touch Visualiser", icon: "hand.point.up")
                }
                NavigationLink {
                    AppearanceOverridesView()
                } label: {
                    row(withLabel: "Appearance", icon: "paintbrush")
                }
                toggleRow("Slow Animations", icon: "tortoise", isOn: $viewModel.slowAnimationsEnabled)
                toggleRow("Show View Frames", icon: "rectangle.dashed", isOn: $viewModel.showViewFrames)
                toggleRow("Show View Sizes", icon: "ruler", isOn: $viewModel.showViewSizes)
            } header: {
                Text("UI/UX")
            }
            
            if !Scyther.developerOptions.isEmpty {
                Section {
                    ForEach(Scyther.developerOptions, id: \.name) { option in
                        developerOptionRow(option)
                    }
                } header: {
                    Text("Development Tools")
                }
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

    func toggleRow(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
    
    @ViewBuilder
    func developerOptionRow(_ option: DeveloperOption) -> some View {
        switch option.type {
        case .value:
            HStack {
                developerOptionLabel(option)
                if let value = option.value {
                    Text(value)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        case .viewController:
            if let viewController = option.viewController {
                NavigationLink {
                    ViewControllerRepresentable(viewController: viewController)
                } label: {
                    developerOptionLabel(option)
                }
            }
        case .swiftUIView:
            if let swiftUIView = option.swiftUIView {
                NavigationLink {
                    swiftUIView
                } label: {
                    developerOptionLabel(option)
                }
            }
        }
    }

    @ViewBuilder
    func developerOptionLabel(_ option: DeveloperOption) -> some View {
        if let systemImage = option.systemImage {
            Label(option.name, systemImage: systemImage)
        } else if let icon = option.icon {
            Label {
                Text(option.name)
            } icon: {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .foregroundStyle(Color.accentColor)
            }
        } else {
            Text(option.name)
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

/// View model for the main menu interface.
///
/// Manages the IP address loading state for display in the networking section.
class NewMenuViewModel: ViewModel {
    /// The device's current IP address.
    @Published var ipAddress: String = ""

    /// Whether the IP address is currently being fetched.
    @Published var isLoadingIPAddress: Bool = true

    /// Whether slow animations mode is enabled.
    @Published var slowAnimationsEnabled: Bool = InterfaceToolkit.slowAnimationsEnabled {
        didSet {
            InterfaceToolkit.slowAnimationsEnabled = slowAnimationsEnabled
        }
    }

    /// Whether view frames are shown.
    @Published var showViewFrames: Bool = InterfaceToolkit.showViewFrames {
        didSet {
            InterfaceToolkit.showViewFrames = showViewFrames
        }
    }

    /// Whether view sizes are shown.
    @Published var showViewSizes: Bool = InterfaceToolkit.showViewSizes {
        didSet {
            InterfaceToolkit.showViewSizes = showViewSizes
        }
    }

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

/// Base view model class for all Scyther view models.
///
/// Provides lifecycle methods for view appearance management:
/// - ``setup()``: Called during initialization
/// - ``onFirstAppear()``: Called only on the first appearance
/// - ``onAppear()``: Called every time the view appears
/// - ``onSubsequentAppear()``: Called on every appearance after the first
///
/// Subclasses should override these methods to implement their specific behavior.
@MainActor
class ViewModel: ObservableObject {
    init() {
        setup()
    }

    /// Called during initialization.
    ///
    /// Override to perform setup tasks that need to happen before the view appears.
    func setup() {

    }

    /// Called the first time the view appears.
    ///
    /// Override to perform one-time initialization tasks like loading data.
    func onFirstAppear() async {

    }

    /// Called every time the view appears.
    ///
    /// Override to perform tasks that should happen on every appearance.
    func onAppear() async {

    }

    /// Called every time the view appears after the first appearance.
    ///
    /// Override to perform refresh tasks that should skip the initial load.
    func onSubsequentAppear() async {

    }
}

/// A SwiftUI wrapper for displaying UIKit view controllers.
///
/// Used internally to present custom ``DeveloperOption`` view controllers
/// within the SwiftUI navigation hierarchy.
struct ViewControllerRepresentable: UIViewControllerRepresentable {
    let viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}
