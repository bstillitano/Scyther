//
//  MenuViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import Combine
import Foundation
import SwiftUI

/// View model for the main menu interface.
///
/// `MenuViewModel` manages the state and data loading for the Scyther developer menu,
/// including network information retrieval and UI toolkit settings synchronization.
///
/// ## Features
///
/// - **Menu Structure**: Supplies the ordered section layout and the set of pinned rows
/// - **Pinning**: Persists pinned rows to Scyther's preferences suite, oldest pin first
/// - **Network Information**: Asynchronously fetches and displays the device's current IP address
/// - **Animation Controls**: Manages slow animations mode for UI debugging
/// - **View Debugging**: Controls visibility of view frames and sizes
/// - **Automatic Synchronization**: Two-way binding with ``InterfaceToolkit`` settings
///
/// ## Usage
///
/// The view model is used by ``MenuView`` to manage its state:
///
/// ```swift
/// struct MenuView: View {
///     @StateObject private var viewModel = MenuViewModel()
///
///     var body: some View {
///         List {
///             // IP address with loading indicator
///             row(
///                 withLabel: "IP Address",
///                 description: viewModel.ipAddress,
///                 andLoadingState: viewModel.isLoadingIPAddress
///             )
///
///             // Toggle controls bound to view model
///             Toggle("Slow Animations", isOn: $viewModel.slowAnimationsEnabled)
///             Toggle("Show View Frames", isOn: $viewModel.showViewFrames)
///             Toggle("Show View Sizes", isOn: $viewModel.showViewSizes)
///         }
///         .onFirstAppear {
///             await viewModel.onFirstAppear()
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Menu Structure
///
/// - ``sections``
/// - ``pinnedItems``
/// - ``pinnedItemIDs``
/// - ``isPinned(_:)``
/// - ``togglePin(for:)``
/// - ``developerOption(named:)``
///
/// ### Search
///
/// - ``searchText``
/// - ``searchResults``
/// - ``assistedResults``
/// - ``displayedSearchResults``
///
/// ### Network Information
///
/// - ``ipAddress``
/// - ``isLoadingIPAddress``
///
/// ### Request Overrides
///
/// - ``enabledOverrideCount``
///
/// ### Network Conditioning
///
/// - ``conditioningSummary``
///
/// ### UI Debugging Controls
///
/// - ``slowAnimationsEnabled``
/// - ``layoutGuidesEnabled``
/// - ``canShowLayoutGuides``
/// - ``activateLayoutRuler()``
/// - ``showsLayoutRulerUnavailableAlert``
/// - ``showViewFrames``
/// - ``showViewSizes``
///
/// ### Lifecycle
///
/// - ``onFirstAppear()``
/// - ``onSubsequentAppear()``
@MainActor
class MenuViewModel: ViewModel {
    // MARK: - Menu Structure

    /// The key backing ``pinnedItemIDs`` in Scyther's preferences store.
    static let pinnedItemsKey = "Scyther.Menu.PinnedItems"

    /// The store pinned item identifiers are read from and written to.
    private let defaults: UserDefaults

    /// The override store the Request Overrides row's badge counts.
    private let networkRuleStore: NetworkRuleStore

    /// The conditioning store the Network Conditioning row's detail text describes.
    private let conditioningStore: NetworkConditioningStore

    /// The breakpoint store this view model mirrors.
    private let breakpointStore: BreakpointStore

    /// Keeps the override store's publishers alive for the lifetime of the menu.
    private var cancellables: Set<AnyCancellable> = []

    /// How many request overrides are currently being applied, persisted and transient together.
    ///
    /// Shown as a badge on the Request Overrides row so overrides are never silently on. A
    /// developer chasing a response that will not change has to be able to see, from the menu's
    /// first screen, that something is rewriting their traffic — the MOCKED badge is only visible
    /// inside the network log, and the master switch only on the overrides screen itself.
    ///
    /// Zero when nothing is enabled, which is what hides the badge — and zero while the master
    /// switch is off, however many overrides are enabled behind it. The badge says what is being
    /// applied, not what is configured; with the switch off nothing is, and a count there would
    /// send that developer looking for an override that is not running.
    @Published private(set) var enabledOverrideCount: Int = 0

    /// How many breakpoints are currently being applied.
    ///
    /// Shown as a badge on the Breakpoints row, for a sharper version of the reason the override
    /// count is shown: an override changes a response, while a breakpoint stops the app until
    /// somebody decides what to do. A developer whose app has just frozen needs to be able to see
    /// why from the menu's first screen.
    ///
    /// Zero while the master switch is off, however many breakpoints are enabled behind it.
    @Published private(set) var enabledBreakpointCount: Int = 0

    /// What the Network Conditioning row shows as its detail text: the active preset, `Custom`,
    /// or `Off`.
    ///
    /// Conditioning applies to every request the app makes, so it has to be visible from the
    /// menu's first screen for the same reason the override count is — a developer who has
    /// forgotten it is on will otherwise spend an afternoon blaming their backend.
    @Published private(set) var conditioningSummary: String = localized("Off")

    /// The identifiers of pinned rows, in the order they were pinned.
    ///
    /// An array rather than a `Set` so that oldest-first pin order survives a relaunch.
    @Published private(set) var pinnedItemIDs: [String]

    /// A snapshot of ``Scyther/developerOptions``, taken once when the view model is created.
    ///
    /// `Scyther.developerOptions` is a `nonisolated(unsafe)` global a host app can mutate at
    /// any time, including while the menu is on screen. ``sections``, ``pinnedItems``, and
    /// ``developerOption(named:)`` all derive from this single stored copy rather than
    /// re-reading the global independently, so they can never disagree about which developer
    /// options exist for the lifetime of this view model. Without that, a section could list a
    /// `.developerOption(name:)` row that a later, independent lookup could no longer resolve —
    /// `MenuView` would render nothing for that row while its swipe-to-pin action, attached
    /// alongside the row content, remains live.
    private let developerOptions: [DeveloperOption]

    /// The full menu layout, including any host-supplied developer options.
    var sections: [MenuSection] {
        MenuSection.allSections(developerOptions: developerOptions)
    }

    /// Resolves a host-supplied developer option by name.
    ///
    /// Looks up the option in ``developerOptions``, the snapshot also used to build
    /// ``sections`` — the same name that appears in a `.developerOption(name:)` row is
    /// therefore always resolvable here, regardless of what a host app has since done to
    /// `Scyther.developerOptions`.
    ///
    /// - Parameter name: A developer option's ``DeveloperOption/name``, as carried by a
    ///   ``MenuItem/developerOption(name:)`` row.
    /// - Returns: The matching option, or `nil` if none was registered under that name when
    ///   this view model was created.
    func developerOption(named name: String) -> DeveloperOption? {
        developerOptions.first { $0.name == name }
    }

    /// The pinned rows, oldest pin first.
    ///
    /// Stored identifiers that no longer resolve to a row currently present in ``sections``
    /// are dropped. This covers both a feature removed in a later version of Scyther and a
    /// developer option the host app no longer registers.
    var pinnedItems: [MenuItem] {
        let available = Set(sections.flatMap(\.items))
        return pinnedItemIDs
            .compactMap(MenuItem.init(id:))
            .filter { available.contains($0) }
    }

    /// Creates a menu view model.
    ///
    /// Snapshots ``Scyther/developerOptions`` at this point — see ``developerOptions``.
    ///
    /// - Parameters:
    ///   - defaults: The store backing pin state. Defaults to Scyther's private
    ///     preferences suite; tests inject a throwaway suite.
    ///   - assistants: The fuzzy-search tiers, in pipeline order. Defaults to the
    ///     tiers available on this device; tests inject mocks.
    ///   - assistedSearchDelay: The typing pause before assistants run. Defaults to
    ///     300 ms; tests inject something shorter.
    init(
        defaults: UserDefaults = .scyther,
        assistants: [any MenuSearchAssistant] = MenuSearchAssistants.available(),
        assistedSearchDelay: Duration = .milliseconds(300),
        networkRuleStore: NetworkRuleStore = .shared,
        conditioningStore: NetworkConditioningStore = .shared,
        breakpointStore: BreakpointStore = .shared
    ) {
        self.defaults = defaults
        self.developerOptions = Scyther.developerOptions
        self.pinnedItemIDs = defaults.stringArray(forKey: Self.pinnedItemsKey) ?? []
        self.assistants = assistants
        self.assistedSearchDelay = assistedSearchDelay
        self.networkRuleStore = networkRuleStore
        self.conditioningStore = conditioningStore
        self.breakpointStore = breakpointStore
        super.init()
    }

    /// Mirrors both networking stores so ``enabledOverrideCount`` and ``conditioningSummary``
    /// are live.
    ///
    /// Subscribing rather than reading once on appearance: an override can be enabled from the
    /// overrides screen, from a swipe on its row, or from `Scyther.network.rules` while the menu
    /// is on screen, and the badge has to follow all three. The master switch is a fourth: it
    /// stops every override being applied without changing one of them, so it has to be joined
    /// here or the badge keeps reading a count for overrides that are standing down. No
    /// `receive(on:)` — the store and this view model are both main-actor isolated, so the values
    /// already arrive on the main thread.
    override func setup() {
        super.setup()
        networkRuleStore.$rules
            .combineLatest(networkRuleStore.$transientRules, networkRuleStore.$isEnabled)
            .sink { [weak self] rules, transient, isEnabled in
                guard isEnabled else {
                    self?.enabledOverrideCount = 0
                    return
                }
                self?.enabledOverrideCount = (rules + transient).filter(\.isEnabled).count
            }
            .store(in: &cancellables)
        conditioningStore.$isEnabled
            .combineLatest(conditioningStore.$condition)
            .sink { [weak self] isEnabled, condition in
                self?.conditioningSummary = NetworkConditioningPreset.summary(isEnabled: isEnabled,
                                                                               condition: condition)
            }
            .store(in: &cancellables)
        breakpointStore.$breakpoints
            .combineLatest(breakpointStore.$isEnabled)
            .sink { [weak self] breakpoints, isEnabled in
                self?.enabledBreakpointCount = isEnabled ? breakpoints.filter(\.isEnabled).count : 0
            }
            .store(in: &cancellables)
    }

    /// Whether the given row is pinned.
    ///
    /// - Parameter item: The row to check.
    /// - Returns: `true` when the row appears in the "Pinned" section.
    func isPinned(_ item: MenuItem) -> Bool {
        pinnedItemIDs.contains(item.id)
    }

    /// Pins or unpins a row, persisting the change immediately.
    ///
    /// Pinning appends the row to the end of the pinned list, so the "Pinned" section reads
    /// oldest pin first. Unpinning leaves the order of the remaining rows untouched.
    ///
    /// - Parameter item: The row to pin or unpin.
    func togglePin(for item: MenuItem) {
        if let index = pinnedItemIDs.firstIndex(of: item.id) {
            pinnedItemIDs.remove(at: index)
        } else {
            pinnedItemIDs.append(item.id)
        }
        defaults.set(pinnedItemIDs, forKey: Self.pinnedItemsKey)
    }

    /// Re-reads ``pinnedItemIDs`` from ``defaults``.
    ///
    /// `MenuView` sits at the root of a `UINavigationController` (see `Scyther.hideMenu()`
    /// and `Scyther.showMenu()`), so its `@StateObject MenuViewModel` survives pushing into,
    /// and popping back from, other screens — including the UserDefaults browser. Without
    /// this, a "Reset all Scyther settings" or a hand-edit of `Scyther.Menu.PinnedItems`
    /// performed while the menu is off screen would go unnoticed: ``pinnedItemIDs`` would
    /// keep reflecting whatever was in memory when the view model was created, and the next
    /// ``togglePin(for:)`` would write that stale array straight back to disk, undoing the
    /// reset.
    private func reloadPinnedItemIDs() {
        pinnedItemIDs = defaults.stringArray(forKey: Self.pinnedItemsKey) ?? []
    }

    // MARK: - Search

    /// The current global-search query, bound to `MenuView`'s search field.
    ///
    /// Every change restarts the assisted-search pipeline — see ``assistedResults``.
    @Published var searchText: String = "" {
        didSet { scheduleAssistedSearch() }
    }

    /// The synchronous search results for ``searchText`` — exact and alias matches.
    ///
    /// Delegates to ``MenuSearchIndex/entries(matching:developerOptions:)`` using the
    /// same developer-options snapshot ``sections`` is built from, so a host-supplied
    /// row is searchable exactly when it is visible. Empty while ``searchText`` is
    /// empty or whitespace.
    var searchResults: [MenuSearchEntry] {
        MenuSearchIndex.entries(matching: searchText, developerOptions: developerOptions)
    }

    /// Results contributed by the fuzzy tiers (``MenuSearchAssistant``), already
    /// deduplicated against ``searchResults`` and each other.
    ///
    /// Populated by a debounced task so the synchronous results never wait on
    /// inference: each edit of ``searchText`` cancels the previous task, clears
    /// these, and — after a short pause in typing — runs each assistant in order,
    /// appending its findings as they arrive. Responses for stale queries are
    /// discarded.
    @Published private(set) var assistedResults: [MenuSearchEntry] = []

    /// Everything search shows, in tier order: exact/alias matches first, then
    /// assisted matches as they arrive.
    var displayedSearchResults: [MenuSearchEntry] {
        searchResults + assistedResults
    }

    /// The fuzzy-search tiers, in pipeline order. Empty when none are available.
    private let assistants: [any MenuSearchAssistant]

    /// How long typing must pause before the assistants run.
    private let assistedSearchDelay: Duration

    /// The in-flight assisted search, if any.
    private var assistedSearchTask: Task<Void, Never>?

    /// Restarts the assisted-search pipeline for the current ``searchText``.
    private func scheduleAssistedSearch() {
        assistedSearchTask?.cancel()
        assistedResults = []

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !assistants.isEmpty else { return }

        let entries = MenuSearchIndex.entries(developerOptions: developerOptions)
        assistedSearchTask = Task { [weak self, assistants, assistedSearchDelay] in
            try? await Task.sleep(for: assistedSearchDelay)
            guard !Task.isCancelled else { return }

            for assistant in assistants {
                let matches = await assistant.matches(for: query, in: entries)
                guard let self, !Task.isCancelled else { return }
                // Drop responses that arrive after the query has moved on.
                guard self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                self.appendAssistedResults(matches)
            }
        }
    }

    /// Appends assistant matches, skipping anything an earlier tier already shows.
    private func appendAssistedResults(_ matches: [MenuSearchEntry]) {
        var shown = Set(displayedSearchResults.map(\.id))
        for match in matches where !shown.contains(match.id) {
            shown.insert(match.id)
            assistedResults.append(match)
        }
    }

    // MARK: - Network Properties

    /// The device's current IP address.
    ///
    /// This property is populated asynchronously during ``onFirstAppear()`` using
    /// ``NetworkHelper`` to fetch the device's IP address. While loading, this
    /// will be an empty string and ``isLoadingIPAddress`` will be `true`.
    @Published var ipAddress: String = ""

    /// Whether the IP address is currently being fetched.
    ///
    /// This property is `true` while the IP address is being loaded from ``NetworkHelper``.
    /// Use this to display a loading indicator in the UI.
    @Published var isLoadingIPAddress: Bool = true

    // MARK: - UI Debugging Properties

    /// Whether slow animations mode is enabled.
    ///
    /// This property is two-way synchronized with ``InterfaceToolkit/slowAnimationsEnabled``.
    /// When enabled, all animations in the app run at a slower speed to aid in debugging
    /// UI transitions and animations.
    ///
    /// Changes to this property automatically update the global toolkit setting.
    @Published var slowAnimationsEnabled: Bool = InterfaceToolkit.slowAnimationsEnabled {
        didSet {
            InterfaceToolkit.slowAnimationsEnabled = slowAnimationsEnabled
        }
    }

    /// Whether the layout guides overlay is visible.
    ///
    /// This property is two-way synchronized with ``Scyther/interface``'s
    /// ``Interface/layoutGuidesEnabled`` facade — the same pattern ``Interface/gridOverlayEnabled``
    /// uses, rather than ``showViewFrames``'s direct binding to a static on ``InterfaceToolkit``,
    /// because ``LayoutGuides`` is a settings singleton like ``GridOverlay``, not a bare
    /// `UserDefaults`-backed static.
    ///
    /// The explicit call to ``InterfaceToolkit/showLayoutGuides()`` is not strictly needed —
    /// ``LayoutGuides/enabled``'s own setter already pushes the change there — but it is kept
    /// here anyway so this binding does not rely on a side effect buried two layers down: if a
    /// future change to ``LayoutGuides`` ever dropped that push, the menu's own toggle would
    /// still work.
    @Published var layoutGuidesEnabled: Bool = Scyther.interface.layoutGuidesEnabled {
        didSet {
            Scyther.interface.layoutGuidesEnabled = layoutGuidesEnabled
            InterfaceToolkit.instance.showLayoutGuides()
        }
    }

    /// Whether the guides row can do anything, so ``MenuView`` can disable it when it cannot.
    ///
    /// The guides' half of the spec's "neither tool activates; the menu row reports it rather than
    /// appearing to work". The ruler answers that with an alert because it has a tap to intercept;
    /// a `Toggle` has none — by the time it calls back the flag has already moved — so the row says
    /// it instead by being disabled, which is the stock way a control states it cannot act. The
    /// setting itself is left alone: it is persisted, and a launch that has a key window should
    /// still find the guides as the developer left them.
    var canShowLayoutGuides: Bool {
        InterfaceToolkit.instance.canShowLayoutGuides
    }

    /// Dismisses the menu and puts the layout ruler on screen.
    ///
    /// Not a toggle, which is why it is a method rather than a `@Published` property: the ruler
    /// consumes every touch on the screen while it is active, so leaving it switched on behind an
    /// open menu would mean the developer dismissed the menu into an app that no longer responds
    /// to anything. Activation and dismissal are one gesture.
    ///
    /// Activated in `hideMenu`'s completion rather than before it, so the overlay starts taking
    /// touches only once the menu has actually gone — an overlay is brought to the front of the
    /// key window, and one activated mid-animation would sit over the dismissal it is interrupting.
    /// The hop through `Task { @MainActor in }` is because that completion is a plain,
    /// non-isolated closure, while ``LayoutRuler`` is main-actor state.
    ///
    /// With no key window there is nothing to draw over, and this reports that instead of
    /// dismissing the menu — ``showsLayoutRulerUnavailableAlert``. The spec's rule for the case is
    /// that the tool "does not activate; the menu row reports it rather than appearing to work",
    /// and the ruler is the worst possible place to fail silently: it would leave
    /// ``LayoutRuler/isActive`` set with no visible Done to clear it.
    func activateLayoutRuler() {
        guard InterfaceToolkit.instance.canShowLayoutRuler else {
            showsLayoutRulerUnavailableAlert = true
            return
        }

        Scyther.hideMenu {
            Task { @MainActor in
                LayoutRuler.instance.isActive = true
            }
        }
    }

    /// Whether to tell the developer the ruler has no window to draw over.
    ///
    /// Driven only by ``activateLayoutRuler()``; ``MenuView`` binds an alert to it.
    @Published var showsLayoutRulerUnavailableAlert: Bool = false

    /// Whether view frames are shown.
    ///
    /// This property is two-way synchronized with ``InterfaceToolkit/showViewFrames``.
    /// When enabled, visual overlays are drawn around all view frames to help with
    /// layout debugging.
    ///
    /// Changes to this property automatically update the global toolkit setting.
    @Published var showViewFrames: Bool = InterfaceToolkit.showViewFrames {
        didSet {
            InterfaceToolkit.showViewFrames = showViewFrames
        }
    }

    /// Whether view sizes are shown.
    ///
    /// This property is two-way synchronized with ``InterfaceToolkit/showViewSizes``.
    /// When enabled, view dimensions are displayed as overlays on each view to help
    /// with layout debugging.
    ///
    /// Changes to this property automatically update the global toolkit setting.
    @Published var showViewSizes: Bool = InterfaceToolkit.showViewSizes {
        didSet {
            InterfaceToolkit.showViewSizes = showViewSizes
        }
    }

    // MARK: - Lifecycle Methods

    /// Called the first time the menu view appears.
    ///
    /// This method initiates the asynchronous loading of the device's IP address.
    /// The loading state is tracked via ``isLoadingIPAddress`` and the result is
    /// stored in ``ipAddress``.
    ///
    /// - Important: Always call `await super.onFirstAppear()` to ensure proper lifecycle tracking.
    override func onFirstAppear() async {
        await super.onFirstAppear()

        await loadIPAddress()
    }

    /// Called every time the menu reappears after the first time.
    ///
    /// Reloads ``pinnedItemIDs`` from ``defaults`` — see ``reloadPinnedItemIDs()`` — so pins
    /// changed while the menu was off screen (a reset of the Scyther store, or a hand-edit of
    /// `Scyther.Menu.PinnedItems` in the UserDefaults browser) are reflected immediately on
    /// return. Deliberately does not re-run ``loadIPAddress()``, which stays confined to
    /// ``onFirstAppear()``.
    ///
    /// - Important: Always call `await super.onSubsequentAppear()` to ensure proper lifecycle
    ///   tracking.
    override func onSubsequentAppear() async {
        await super.onSubsequentAppear()

        reloadPinnedItemIDs()
    }

    // MARK: - Private Methods

    /// Loads the device's IP address from ``NetworkHelper``.
    ///
    /// This method fetches the IP address asynchronously and updates ``ipAddress``
    /// and ``isLoadingIPAddress`` accordingly. The loading state is automatically
    /// set to `false` when the operation completes, regardless of success or failure.
    private func loadIPAddress() async {
        defer { isLoadingIPAddress = false }
        isLoadingIPAddress = true
        ipAddress = await NetworkHelper.instance.ipAddress
    }
}
