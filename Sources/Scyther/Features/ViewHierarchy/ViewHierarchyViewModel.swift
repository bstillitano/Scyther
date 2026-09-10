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
///   Production uses the default, which is the package's shared
///   ``UIKit/UIApplication/scytherKeyWindow``.
@MainActor
final class ViewHierarchyViewModel: ViewModel {
    /// One of the three states that make a view interesting enough to mark on its row.
    ///
    /// Modelled rather than left as loose strings so a badge's word has one definition: the page
    /// draws it, ``accessibilityLabel(for:)`` speaks it, and the two can never disagree — which is
    /// the whole failure mode a purely visual badge has under VoiceOver.
    enum Badge: String, Identifiable, Sendable {
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

    /// The line one view is drawn as, wherever it is drawn: what the label shows, what VoiceOver
    /// reads, and the node the row opens.
    ///
    /// The page draws from these rather than from ``ViewNode`` directly. A `ViewNode` carries its
    /// whole subtree, so a row built straight from the root's node held four hundred nodes to draw
    /// one line of text, and every field the row shows — the size string, the badge list — was
    /// worked out again on each redraw. A row is worked out once, when the visible set changes.
    ///
    /// It carries **only what both of the page's two lists draw**. The tree's own three fields —
    /// indentation, whether there is a subtree, whether it is open — live on ``TreeRow`` instead,
    /// because a search result is a flat list with no disclosure control and no place in a tree,
    /// and a row type carrying fields that are meaningless in one of its two contexts invites the
    /// page to read one of them there.
    ///
    /// ``node`` is still the full node, because ``ViewDetailView`` takes one; it is read only when
    /// the row is tapped.
    struct Row: Identifiable, Equatable {
        /// The described view's identity, which is also the row's identity in the `List`.
        let id: ObjectIdentifier

        /// The class name the row shows.
        let className: String

        /// The row's size text, e.g. `"200 × 20"`.
        let size: String

        /// The badges the row wears.
        let badges: [Badge]

        /// What VoiceOver reads: the class name, the size, then any badge words.
        let accessibilityLabel: String

        /// The node the row opens. Read only when the row is tapped.
        let node: ViewNode
    }

    /// One row of the drawn tree: the line, and where in the tree it sits.
    struct TreeRow: Identifiable, Equatable {
        /// The described view's identity, which is also the row's identity in the `List`.
        var id: ObjectIdentifier { row.id }

        /// The line the row draws.
        let row: Row

        /// How far the row is indented, already capped by ``ViewNode/indentationLevel(forDepth:)``.
        let indentationLevel: Int

        /// Whether the row has a subtree to open. Rows without one carry no disclosure control.
        let hasChildren: Bool

        /// Whether the row's subtree is currently showing.
        let isExpanded: Bool
    }

    /// One search result: the line that draws the hit, and the chain of ancestors above it.
    struct MatchRow: Identifiable, Equatable {
        /// The matched view's identity.
        var id: ObjectIdentifier { row.id }

        /// The line drawing the matched node.
        let row: Row

        /// The class names of the node's ancestors, root first, excluding the node itself.
        let path: [String]
    }

    /// The deepest level opened when a snapshot is loaded.
    ///
    /// `1` means the root and its immediate children are open and the third level is closed —
    /// "the first two levels" as the page describes it. Rows deeper than this are reachable in
    /// one tap each, or by search, which ignores expansion entirely.
    static let defaultExpansionDepth: Int = 1

    /// The current search query, bound to the page's `.searchable` field.
    ///
    /// ``matchRows`` is recomputed the moment this changes rather than on every read: search walks
    /// the whole tree, and SwiftUI reads a view model's properties far more often than the user
    /// types into it.
    @Published var searchText: String = "" {
        didSet { recomputeMatchRows() }
    }

    /// What ``searchText`` currently matches, in tree order, each with its ancestor path. What the
    /// page iterates while searching.
    ///
    /// Empty while ``isSearching`` is `false` — a blank field means "not searching", not
    /// "everything".
    @Published private(set) var matchRows: [MatchRow] = []

    /// The root of the loaded snapshot, or `nil` before the first load and after a load that
    /// found no key window.
    @Published private(set) var snapshotRoot: ViewNode?

    /// The rows the tree draws: every open node's subtree, flattened, parents before children.
    /// What the page iterates.
    ///
    /// A closed node's children are absent from this list rather than merely hidden, so the page
    /// draws only what it shows.
    ///
    /// This is the **only** published form of the visible tree. An earlier draft published the
    /// flattened `[ViewNode]` beside it, and the two came apart at the first branch that had to
    /// maintain them by hand — see ``loadFromKeyWindow()``. One representation cannot disagree
    /// with itself.
    @Published private(set) var visibleRows: [TreeRow] = []

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
    /// Keyed by identity rather than by index path so expansion survives a refresh: a view still on
    /// screen after a re-walk keeps its open state, and one that has gone drops out — see
    /// ``load(from:windowBounds:)``. Somebody who pulls to refresh after changing something on
    /// screen has asked for a newer tree, not for their place in a four-hundred-row one to be lost.
    ///
    /// The identity is a `UIView`'s address, so an address freed between two walks and handed to a
    /// different view would carry that view's open state onto an unrelated row. That is the whole
    /// cost of being wrong here — one row drawn open that the developer did not open — and it is
    /// worth less than resetting a tree the developer has arranged.
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
    ///
    /// It clears the page through the same two functions a successful load rebuilds it with,
    /// rather than by assigning each published property by hand: every one of them then has
    /// exactly one place it is written, and this branch cannot forget one.
    func loadFromKeyWindow() {
        guard let window = keyWindow() else {
            snapshot = nil
            snapshotRoot = nil
            nodeCount = 0
            takenAt = nil
            expandedNodes = []
            recomputeVisibleRows()
            recomputeMatchRows()
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
    /// The **first** load opens the tree to ``defaultExpansionDepth``. A later one — pull to
    /// refresh — keeps whatever the developer has opened, minus the nodes the new walk no longer
    /// found: a refresh answers "what is on screen now", not "please close everything I opened".
    /// Nodes that have gone drop out rather than accumulating, so the set stays the size of the
    /// tree. See ``expandedNodes`` for the one way this can be wrong and why that is acceptable.
    ///
    /// - Parameters:
    ///   - root: The view to walk.
    ///   - windowBounds: The window space every frame is converted into.
    func load(from root: UIView, windowBounds: CGRect) {
        let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: windowBounds)
        let isFirstLoad = snapshotRoot == nil

        self.snapshot = snapshot
        self.windowBounds = windowBounds
        hasNoKeyWindow = false
        snapshotRoot = snapshot.root
        nodeCount = snapshot.nodeCount
        takenAt = snapshot.takenAt
        if isFirstLoad {
            expandedNodes = Self.identities(in: snapshot.root, toDepth: Self.defaultExpansionDepth)
        } else {
            expandedNodes = expandedNodes.intersection(Self.identities(in: snapshot.root, toDepth: .max))
        }

        recomputeVisibleRows()
        recomputeMatchRows()
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
        // Animated here rather than at the button, because the rows a toggle reveals are siblings
        // in the same `List` — not content nested inside a disclosure group — so nothing else is
        // in a position to animate them, and without this the chevron turns while the rows appear
        // instantly.
        withAnimation {
            recomputeVisibleRows()
        }
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

    // MARK: - Private

    /// Rebuilds ``visibleRows`` from the snapshot and the open set.
    private func recomputeVisibleRows() {
        guard let root = snapshotRoot else {
            visibleRows = []
            return
        }

        var rows: [TreeRow] = []
        func append(_ node: ViewNode) {
            rows.append(treeRow(for: node))
            guard isExpanded(node) else { return }
            for child in node.children { append(child) }
        }
        append(root)
        visibleRows = rows
    }

    /// Builds the line that draws a node.
    ///
    /// - Parameter node: The node to draw.
    /// - Returns: Its row.
    private func row(for node: ViewNode) -> Row {
        Row(id: node.id,
            className: node.className,
            size: sizeDescription(for: node),
            badges: badges(for: node),
            accessibilityLabel: accessibilityLabel(for: node),
            node: node)
    }

    /// Builds the tree row that draws a node, with its place in the tree.
    ///
    /// - Parameter node: The node to draw.
    /// - Returns: Its tree row.
    private func treeRow(for node: ViewNode) -> TreeRow {
        TreeRow(row: row(for: node),
                indentationLevel: ViewNode.indentationLevel(forDepth: node.depth),
                hasChildren: !node.children.isEmpty,
                isExpanded: isExpanded(node))
    }

    /// Rebuilds ``matchRows`` from the snapshot and the current query.
    private func recomputeMatchRows() {
        guard let root = snapshotRoot else {
            matchRows = []
            return
        }
        matchRows = ViewNodeSearch.matches(for: searchText, in: root)
            .map { MatchRow(row: row(for: $0.node), path: $0.path) }
    }

    /// Every node identity at or above `depth`.
    ///
    /// Called with ``defaultExpansionDepth`` to open a fresh snapshot on its first levels, and with
    /// `.max` to collect the whole tree's identities, which is what a refresh intersects the open
    /// set against.
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

    /// The app's key window, through the package's one shared lookup.
    private static var applicationKeyWindow: UIWindow? {
        UIApplication.scytherKeyWindow
    }
}
#endif
