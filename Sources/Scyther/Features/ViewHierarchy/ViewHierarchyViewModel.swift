//
//  ViewHierarchyViewModel.swift
//  Scyther
//

#if !os(macOS)
import SwiftUI
import UIKit

/// Drives the view hierarchy inspector's tree page.
///
/// Holds one walk of the key window and the two pieces of state the page reads from it: which
/// nodes are open, and what the search field currently matches.
///
/// Three deliberate decisions live here:
///
/// - **A snapshot, never a live tree.** ``load(from:windowBounds:)`` walks once and nothing
///   re-walks on its own. Keeping a tree in step with UIKit needs either a timer or swizzled
///   layout methods, and a full walk on every layout pass is exactly the hot-path mistake the
///   accessibility audit taught this project in 4.3.0. The page is full-screen, so nothing is
///   driving the app while the tree is being read; ``takenAt`` is published so the page can say
///   how old the answer is rather than implying it is live.
/// - **Two levels open, the rest closed.** Most of a real window is framework scaffolding nobody
///   wrote, and a fully expanded tree opens onto a screen of it. See ``defaultExpansionDepth``.
/// - **The window is injected.** ``init(keyWindow:)`` takes the lookup as a closure, so the
///   no-key-window path — the spec's own edge case — is testable without standing up a scene.
///   Production uses the default, which resolves the key window exactly the way `InterfaceToolkit`,
///   `AccessibilityAudit` and `Scyther` itself each already do.
@MainActor
final class ViewHierarchyViewModel: ViewModel {
    /// One of the three states that make a view interesting enough to mark on its row.
    ///
    /// Modelled rather than left as loose strings so a badge's word has one definition: the page
    /// draws it, ``accessibilityLabel(for:)`` speaks it, and the two can never disagree — which is
    /// the whole failure mode a purely visual badge has under VoiceOver.
    enum Badge: String, Identifiable, CaseIterable, Sendable {
        /// `isHidden`, or an effective alpha at or below 0.01 anywhere in the view's ancestry.
        case hidden

        /// A width or a height of zero.
        case zeroSize

        /// A window-space frame that does not intersect the window's bounds.
        case offScreen

        /// The badge's own raw name, stable and never shown to the user.
        var id: String { rawValue }

        /// The word the badge shows and VoiceOver speaks, in the effective language.
        var word: String {
            switch self {
            case .hidden: return localized("hidden")
            case .zeroSize: return localized("zero size")
            case .offScreen: return localized("off screen")
            }
        }
    }

    /// The deepest level opened when a snapshot is loaded.
    ///
    /// `1` means the root and its immediate children are open and the third level is closed —
    /// "the first two levels" as the page describes it. Rows deeper than this are reachable in
    /// one tap each, or by search, which ignores expansion entirely.
    static let defaultExpansionDepth: Int = 1

    /// The current search query, bound to the page's `.searchable` field.
    ///
    /// ``matches`` is recomputed the moment this changes rather than on every read: search walks
    /// the whole tree, and SwiftUI reads a view model's properties far more often than the user
    /// types into it.
    @Published var searchText: String = "" {
        didSet { recomputeMatches() }
    }

    /// What ``searchText`` currently matches, in tree order, each with its ancestor path.
    ///
    /// Empty while ``isSearching`` is `false` — a blank field means "not searching", not
    /// "everything".
    @Published private(set) var matches: [ViewNodeSearch.Match] = []

    /// The root of the loaded snapshot, or `nil` before the first load and after a load that
    /// found no key window.
    @Published private(set) var snapshotRoot: ViewNode?

    /// The rows the tree draws: every open node's subtree, flattened, parents before children.
    ///
    /// A closed node's children are absent from this list rather than merely hidden, so the page
    /// draws only what it shows.
    @Published private(set) var visibleNodes: [ViewNode] = []

    /// How many views the snapshot holds, including the root. `0` when nothing is loaded.
    @Published private(set) var nodeCount: Int = 0

    /// When the snapshot was walked, or `nil` when nothing is loaded.
    @Published private(set) var takenAt: Date?

    /// Whether the last ``loadFromKeyWindow()`` found no key window to walk.
    ///
    /// The page reports this rather than showing an empty tree, which would read as "this app has
    /// no views" instead of "there was nothing to look at".
    @Published private(set) var hasNoKeyWindow: Bool = false

    /// The snapshot the tree came from, handed to ``ViewDetailView`` so it can resolve a node back
    /// to its live view for the thumbnail. `nil` before the first successful load.
    private(set) var snapshot: ViewHierarchySnapshot?

    /// The window space every frame in the snapshot is measured in, handed to ``ViewDetailView``
    /// so its position map draws against the same screen the walk measured.
    private(set) var windowBounds: CGRect = .zero

    /// The identities of the open nodes.
    ///
    /// Keyed by identity rather than by index path so expansion survives a refresh: a view still
    /// on screen after a re-walk keeps its open state, and one that has gone simply never comes
    /// up again.
    private var expandedNodes: Set<ObjectIdentifier> = []

    /// Resolves the window to walk. Injected — see the type-level documentation.
    private let keyWindow: @MainActor () -> UIWindow?

    /// Creates the view model.
    ///
    /// - Parameter keyWindow: The window lookup. Defaults to the app's key window.
    init(keyWindow: @escaping @MainActor () -> UIWindow? = { ViewHierarchyViewModel.applicationKeyWindow }) {
        self.keyWindow = keyWindow
        super.init()
    }

    /// Whether the search field holds anything worth searching for.
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Walks the key window on first appearance.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        loadFromKeyWindow()
    }

    /// Walks the key window, replacing whatever is loaded.
    ///
    /// Also the pull-to-refresh action. When there is no key window this loads nothing and raises
    /// ``hasNoKeyWindow`` instead, leaving the page to say so.
    func loadFromKeyWindow() {
        guard let window = keyWindow() else {
            snapshot = nil
            snapshotRoot = nil
            visibleNodes = []
            nodeCount = 0
            takenAt = nil
            expandedNodes = []
            recomputeMatches()
            hasNoKeyWindow = true
            return
        }
        load(from: window, windowBounds: window.bounds)
    }

    /// Walks any root, measuring against the bounds given.
    ///
    /// Split from ``loadFromKeyWindow()`` the same way ``ViewHierarchyWalker/snapshot(of:windowBounds:isOwned:)``
    /// is split from its window entry point, so the page's behaviour can be exercised against a
    /// synthetic hierarchy.
    ///
    /// Expansion is reset to ``defaultExpansionDepth`` on every load, including a refresh: a
    /// refresh is a new answer to the same question, and carrying forward the open state of a tree
    /// the developer has since navigated away from would open a scattering of unrelated rows.
    ///
    /// - Parameters:
    ///   - root: The view to walk.
    ///   - windowBounds: The window space every frame is converted into.
    func load(from root: UIView, windowBounds: CGRect) {
        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)

        self.snapshot = snapshot
        self.windowBounds = windowBounds
        hasNoKeyWindow = false
        snapshotRoot = snapshot.root
        nodeCount = snapshot.nodeCount
        takenAt = snapshot.takenAt
        expandedNodes = Self.identities(in: snapshot.root, toDepth: Self.defaultExpansionDepth)

        recomputeVisibleNodes()
        recomputeMatches()
    }

    /// Whether a node's children are showing.
    ///
    /// - Parameter node: The node to ask about.
    /// - Returns: `true` when the node is open.
    func isExpanded(_ node: ViewNode) -> Bool {
        expandedNodes.contains(node.id)
    }

    /// Opens a closed node, or closes an open one.
    ///
    /// - Parameter node: The node to flip.
    func toggleExpansion(_ node: ViewNode) {
        if expandedNodes.contains(node.id) {
            expandedNodes.remove(node.id)
        } else {
            expandedNodes.insert(node.id)
        }
        recomputeVisibleNodes()
    }

    /// The badges a node's row wears, in the order the row draws them.
    ///
    /// - Parameter node: The node to describe.
    /// - Returns: Its badges, empty for an ordinary visible view.
    func badges(for node: ViewNode) -> [Badge] {
        var badges: [Badge] = []
        if node.isHidden { badges.append(.hidden) }
        if node.isZeroSize { badges.append(.zeroSize) }
        if node.isOffScreen { badges.append(.offScreen) }
        return badges
    }

    /// A node's size, in whole points, as the row shows it.
    ///
    /// Rounded to integers because sub-point sizes are noise at row scale, and never localised:
    /// it is two numbers and a multiplication sign, which read the same in every language. The
    /// exact values, unrounded, are on the detail page.
    ///
    /// - Parameter node: The node to describe.
    /// - Returns: Its size, e.g. `"200 × 20"`.
    func sizeDescription(for node: ViewNode) -> String {
        "\(Int(node.size.width)) × \(Int(node.size.height))"
    }

    /// What VoiceOver reads for a node's row.
    ///
    /// The badges are part of it deliberately. A badge that is only a coloured lozenge tells a
    /// sighted developer that a view is hidden and tells everyone else nothing, so the words go
    /// into the row's label as well as onto its surface.
    ///
    /// - Parameter node: The node the row draws.
    /// - Returns: Its class name, its size, then any badge words.
    func accessibilityLabel(for node: ViewNode) -> String {
        ([node.className, sizeDescription(for: node)] + badges(for: node).map(\.word))
            .joined(separator: ", ")
    }

    /// A binding a stock `DisclosureGroup` can drive, so the chevron reads and writes the same
    /// expansion state the rest of the page does.
    ///
    /// - Parameter node: The node the group draws.
    /// - Returns: A binding onto that node's open state.
    func expansionBinding(for node: ViewNode) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isExpanded(node) ?? false },
            set: { [weak self] shouldExpand in
                guard let self, self.isExpanded(node) != shouldExpand else { return }
                self.toggleExpansion(node)
            }
        )
    }

    // MARK: - Private

    /// Rebuilds ``visibleNodes`` from the snapshot and the open set.
    private func recomputeVisibleNodes() {
        guard let root = snapshotRoot else {
            visibleNodes = []
            return
        }

        var rows: [ViewNode] = []
        func append(_ node: ViewNode) {
            rows.append(node)
            guard isExpanded(node) else { return }
            for child in node.children { append(child) }
        }
        append(root)
        visibleNodes = rows
    }

    /// Rebuilds ``matches`` from the snapshot and the current query.
    private func recomputeMatches() {
        guard let root = snapshotRoot else {
            matches = []
            return
        }
        matches = ViewNodeSearch.matches(for: searchText, in: root)
    }

    /// Every node identity at or above `depth`, so a fresh snapshot opens on its first levels.
    ///
    /// - Parameters:
    ///   - root: The tree to collect from.
    ///   - depth: The deepest level to open.
    /// - Returns: The identities to mark open.
    private static func identities(in root: ViewNode, toDepth depth: Int) -> Set<ObjectIdentifier> {
        var identities: Set<ObjectIdentifier> = []
        func collect(_ node: ViewNode) {
            guard node.depth <= depth else { return }
            identities.insert(node.id)
            for child in node.children { collect(child) }
        }
        collect(root)
        return identities
    }

    /// The app's key window, resolved the same way `InterfaceToolkit`, `AccessibilityAudit` and
    /// `Scyther` itself each do.
    ///
    /// Repeated rather than shared, matching how those three already each keep their own private
    /// copy — there is no existing shared accessor to reuse, and one is not worth introducing for
    /// a single-expression lookup.
    private static var applicationKeyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif
