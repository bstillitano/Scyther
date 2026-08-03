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
/// - **Development Tools**: Custom developer options configured via ``Scyther/developerOptions``
/// - **Networking**: Network tools, logs, and configuration
/// - **Data**: Feature flags, UserDefaults, cookies
/// - **Security**: Keychain browser
/// - **System Tools**: Location spoofer, console logs
/// - **Notifications**: Notification logger and tester
/// - **UI/UX**: Fonts, components, grid overlay, touch visualizer
///
/// The menu displays device information in a header and provides navigation
/// to all sub-features.
///
/// Any row can be pinned via a trailing swipe action. Pinned rows appear in a "Pinned"
/// section rendered directly beneath **Device**, and also remain in their home section, so
/// the menu's structure never changes shape as rows are pinned. Pins are ordered oldest
/// first and persist across launches in `UserDefaults.scyther`.
///
/// A search field (iOS-Settings style) filters a global index covering every menu row
/// and the static rows inside settings sub-pages; each result shows its navigation
/// path, and sub-page results push the page containing the matched row.
public struct MenuView: View {
    @StateObject private var viewModel: MenuViewModel = MenuViewModel()

    public init() {}

    /// Whether the menu is showing search results instead of its sections.
    ///
    /// Driven by the query text rather than `@Environment(\.isSearching)`: focusing
    /// the empty search field keeps the browsable menu visible, matching Settings.
    private var isSearchActive: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        List {
            if isSearchActive {
                searchResultsSection
            } else {
                menuSections
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search")
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
        .onSubsequentAppear {
            await viewModel.onSubsequentAppear()
        }
        .navigationTitle("Scyther")
        .interactiveDismissDisabled()
    }

    /// The normal browsing content: device header, Pinned, and every menu section.
    /// This is the exact content the `List` held before search was added.
    @ViewBuilder
    private var menuSections: some View {
        if let deviceSection = viewModel.sections.first {
            Section {
                header
                ForEach(deviceSection.items) { item in
                    pinnableRow(for: item)
                }
            } header: {
                Text(deviceSection.title)
            }
        }

        if !viewModel.pinnedItems.isEmpty {
            Section {
                ForEach(viewModel.pinnedItems, id: \.pinnedRowID) { item in
                    pinnableRow(for: item)
                }
            } header: {
                Text("Pinned")
            }
        }

        ForEach(Array(viewModel.sections.dropFirst())) { section in
            Section {
                ForEach(section.items) { item in
                    pinnableRow(for: item)
                }
            } header: {
                Text(section.title)
            }
        }
    }

    /// The search results, or a "no results" placeholder.
    ///
    /// Result rows are deliberately not pinnable — pinning stays a browsing gesture,
    /// matching the iOS Settings app.
    @ViewBuilder
    private var searchResultsSection: some View {
        let results = viewModel.searchResults
        if results.isEmpty {
            noResults
        } else {
            Section {
                ForEach(results) { entry in
                    searchResultRow(for: entry)
                }
            }
        }
    }

    /// A single search result.
    ///
    /// Main-page entries reuse ``rowContent(for:)`` so a toggle result is a live
    /// toggle and a value result shows its value; sub-page entries push the page
    /// containing the matched row via ``destination(for:)``.
    @ViewBuilder
    private func searchResultRow(for entry: MenuSearchEntry) -> some View {
        if entry.isSubpageEntry {
            NavigationLink {
                destination(for: entry.target)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if let icon = entry.icon {
                        Label(entry.title, systemImage: icon)
                    } else {
                        Text(entry.title)
                    }
                    breadcrumb(for: entry)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                rowContent(for: entry.target)
                breadcrumb(for: entry)
            }
        }
    }

    /// The navigation path shown beneath a result's title, e.g. "UI/UX → Grid Overlay".
    private func breadcrumb(for entry: MenuSearchEntry) -> some View {
        Text(entry.breadcrumbText)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    /// Shown when the query matches nothing.
    @ViewBuilder
    private var noResults: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            Text("No results for \"\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Wraps a row in its pin/unpin swipe action.
    ///
    /// The action's label is derived from the row's current pin state rather than from which
    /// section it is being rendered in, because pinned rows remain in their home section — a
    /// pinned row therefore reads "Unpin" in both places.
    @ViewBuilder
    private func pinnableRow(for item: MenuItem) -> some View {
        rowContent(for: item)
            .swipeActions(edge: .trailing) {
                Button {
                    viewModel.togglePin(for: item)
                } label: {
                    Label(
                        viewModel.isPinned(item) ? "Unpin" : "Pin",
                        systemImage: viewModel.isPinned(item) ? "pin.slash" : "pin"
                    )
                }
                .tint(.blue)
            }
    }

    /// Builds a row that pushes a destination view.
    ///
    /// The label is derived entirely from the item, so every navigation row in the
    /// menu is laid out identically and only the destination varies.
    private func navigationRow(for item: MenuItem) -> some View {
        NavigationLink {
            destination(for: item)
        } label: {
            row(withLabel: item.title, icon: item.icon)
        }
    }

    /// The single item→destination mapping, shared by ``navigationRow(for:)`` and
    /// search results (a sub-page result pushes the page containing the matched row).
    ///
    /// Items that are not navigation rows (value rows, toggles, tokens, developer
    /// options) return an `EmptyView`; no search entry targets them for navigation.
    @ViewBuilder
    private func destination(for item: MenuItem) -> some View {
        switch item {
        case .networkLogs: NetworkLogsView()
        case .serverConfiguration: ServerConfigurationView()
        case .environmentVariables: EnvironmentVariablesView()
        case .featureFlags: FeatureFlagsView()
        case .userDefaults: UserDefaultsView()
        case .cookies: CookieBrowserView()
        case .fileBrowser: FileBrowserView()
        case .databaseBrowser: DatabaseBrowserView()
        case .keychainBrowser: KeychainBrowserView()
        case .locationSpoofer: LocationSpooferView()
        case .consoleLogs: ConsoleLoggerView()
        case .deepLinkTester: DeepLinkTesterView()
        case .crashLogs: CrashLogsView()
        case .notificationLogger: NotificationLoggerView()
        case .notificationTester: NotificationTesterView()
        case .fonts: FontsView()
        case .interfaceComponents: InterfacePreviewsView()
        case .gridOverlay: GridOverlaySettingsView()
        case .fpsCounter: FPSCounterSettingsView()
        case .touchVisualiser: TouchVisualiserView()
        case .appearance: AppearanceOverridesView()
        default: EmptyView()
        }
    }

    /// The single definition of every menu row.
    ///
    /// ``MenuItem`` supplies each row's title and icon; this method supplies everything
    /// dynamic — a value row's description, a navigation row's destination, a toggle row's
    /// binding. Because there is one definition, the "Pinned" section and a row's home
    /// section always render identically.
    @ViewBuilder
    private func rowContent(for item: MenuItem) -> some View {
        switch item {
        // MARK: Device
        case .osVersion:
            row(withLabel: item.title, description: UIDevice.current.systemVersion)
        case .hardware:
            row(withLabel: item.title, description: UIDevice.current.modelName)
        case .releaseYear:
            row(withLabel: item.title, description: UIDevice.current.generation.withoutDecimals)
        case .uuid:
            row(withLabel: item.title, description: UIDevice.current.identifierForVendor?.uuidString)

        // MARK: Application
        case .appIdPrefix:
            row(withLabel: item.title, description: Bundle.main.seedId)
        case .displayName:
            row(withLabel: item.title, description: String(UIApplication.shared.appName))
        case .bundleId:
            row(withLabel: item.title, description: Bundle.main.bundleIdentifier)
        case .processId:
            row(withLabel: item.title, description: String(getpid()))
        case .version:
            row(withLabel: item.title, description: Bundle.main.versionNumber)
        case .buildNumber:
            row(withLabel: item.title, description: Bundle.main.buildNumber)
        case .buildDate:
            row(withLabel: item.title, description: Bundle.main.buildDate.formatted())
        case .releaseType:
            row(withLabel: item.title, description: AppEnvironment.configuration().rawValue)

        // MARK: Development Tools
        case .developerOption(let name):
            // Resolved from `viewModel`'s snapshot of `Scyther.developerOptions`, the same
            // snapshot `sections` was built from, rather than re-reading the global directly.
            // A host app can mutate `Scyther.developerOptions` while this menu is on screen;
            // reading the same snapshot here guarantees this lookup always succeeds for a name
            // that `sections` listed, so a row is never left blank while `pinnableRow` has
            // already attached a live swipe action to it.
            if let option = viewModel.developerOption(named: name) {
                developerOptionRow(option)
            }

        // MARK: Networking
        case .ipAddress:
            row(
                withLabel: item.title,
                description: viewModel.ipAddress,
                icon: item.icon,
                andLoadingState: viewModel.isLoadingIPAddress
            )
        case .networkLogs:
            navigationRow(for: item)
        case .serverConfiguration:
            navigationRow(for: item)
        case .environmentVariables:
            navigationRow(for: item)

        // MARK: Data
        case .featureFlags:
            navigationRow(for: item)
        case .userDefaults:
            navigationRow(for: item)
        case .cookies:
            navigationRow(for: item)
        case .fileBrowser:
            navigationRow(for: item)
        case .databaseBrowser:
            navigationRow(for: item)

        // MARK: Security
        case .keychainBrowser:
            navigationRow(for: item)

        // MARK: System Tools
        case .locationSpoofer:
            navigationRow(for: item)
        case .consoleLogs:
            navigationRow(for: item)
        case .deepLinkTester:
            navigationRow(for: item)
        case .crashLogs:
            navigationRow(for: item)

        // MARK: Notifications
        case .notificationLogger:
            navigationRow(for: item)
        case .notificationTester:
            navigationRow(for: item)
        case .apnsToken:
            row(withLabel: item.title, icon: item.icon)
        case .fcmToken:
            row(withLabel: item.title, icon: item.icon)

        // MARK: UI/UX
        case .fonts:
            navigationRow(for: item)
        case .interfaceComponents:
            navigationRow(for: item)
        case .gridOverlay:
            navigationRow(for: item)
        case .fpsCounter:
            navigationRow(for: item)
        case .touchVisualiser:
            navigationRow(for: item)
        case .appearance:
            navigationRow(for: item)
        case .slowAnimations:
            toggleRow(item.title, icon: item.icon, isOn: $viewModel.slowAnimationsEnabled)
        case .showViewFrames:
            toggleRow(item.title, icon: item.icon, isOn: $viewModel.showViewFrames)
        case .showViewSizes:
            toggleRow(item.title, icon: item.icon, isOn: $viewModel.showViewSizes)
        }
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

    /// Builds a toggle row bound to a Boolean setting.
    ///
    /// - Parameters:
    ///   - label: The row's title.
    ///   - icon: An optional SF Symbol shown alongside the label. Rows without an icon
    ///     (there are currently none among toggle rows, but ``MenuItem/icon`` is optional)
    ///     render as plain text.
    ///   - isOn: The binding the toggle reads from and writes to.
    func toggleRow(_ label: String, icon: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            if let icon {
                Label {
                    Text(label)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Text(label)
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
