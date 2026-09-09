//
//  ViewHierarchyView.swift
//  Scyther
//

#if !os(macOS)
import SwiftUI
import UIKit

/// The view hierarchy inspector's tree page.
///
/// One snapshot of the key window, opened to its first two levels, with a `.searchable` field over
/// class names and the text views carry. Selecting any row pushes ``ViewDetailView``.
///
/// The tree is drawn as a **flat list of the currently visible rows** rather than as nested
/// `DisclosureGroup`s. Nesting would hand SwiftUI the indentation for free, but its indent grows
/// without limit, and a view forty levels down a real screen would have its class name pushed off
/// the right of a phone. Indenting each row explicitly is what lets
/// ``ViewNode/indentationLevel(forDepth:)`` cap the indent at eight levels while the row keeps its
/// true depth.
///
/// **Each row carries two separate controls, side by side, rather than one inside the other.** A
/// `DisclosureGroup` whose label was the row's `NavigationLink` drew the collapsed state as a
/// right-pointing chevron identical to the link's own navigation accessory: one glyph with two
/// meanings, and a collapsed parent indistinguishable from a leaf, on a page whose whole job is
/// telling you what is under something. So the disclosure is a plain leading `Button` carrying a
/// chevron that rotates as it opens, navigation keeps the link's trailing accessory, and a leaf has
/// no leading control at all. Two unambiguous targets, two unambiguous glyphs, and two distinct
/// accessibility labels, so a screen reader is not left with the ambiguity either.
struct ViewHierarchyView: View {
    @StateObject private var viewModel = ViewHierarchyViewModel()

    /// How far one level of depth indents a row.
    private static let indentationStep: CGFloat = 14

    /// The width the disclosure control occupies, and the width a leaf row leaves blank in its
    /// place so that class names line up down the tree.
    private static let disclosureWidth: CGFloat = 30

    var body: some View {
        List {
            if viewModel.hasNoKeyWindow {
                Section {
                    Text(localized("There is no key window to inspect right now."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if let snapshot = viewModel.snapshot {
                // Every row is built from a snapshot that already exists, so no row can push a page
                // with nothing on it. Guarding inside a `NavigationLink`'s destination instead
                // would leave the row tappable and land on a back button and blank space.
                Section {
                    if viewModel.isSearching {
                        searchResults(in: snapshot)
                    } else {
                        ForEach(viewModel.visibleRows) { row in
                            treeRow(row, in: snapshot)
                        }
                    }
                } header: {
                    header
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: localized("Search classes and text"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable {
            viewModel.loadFromKeyWindow()
        }
        .navigationTitle(localized("View Hierarchy"))
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    // MARK: - Header

    /// How much the snapshot holds and when it was taken.
    ///
    /// The time is stated because a snapshot that does not say it is a snapshot is a lie: nothing
    /// re-walks on its own, so a tree read after the app has moved on describes where things
    /// *were*. Pull to refresh takes a new one.
    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized("\(viewModel.nodeCount) views"))
            if let takenAt = viewModel.takenAt {
                Text(localized("Snapshot taken \(takenAt.formatted(date: .omitted, time: .standard))"))
            }
        }
    }

    // MARK: - Tree

    /// One row of the tree: its disclosure control when it has children, then its link, indented to
    /// its capped depth.
    private func treeRow(_ row: ViewHierarchyViewModel.Row,
                         in snapshot: ViewHierarchySnapshot) -> some View {
        HStack(spacing: 0) {
            if row.hasChildren {
                disclosure(for: row)
            } else {
                // Keeps a leaf's class name in the same column as its siblings'. Blank rather than
                // a dimmed chevron: a leaf has nothing to open, and drawing a disabled control
                // where there is no control is how the old construction misled in the first place.
                Color.clear
                    .frame(width: Self.disclosureWidth, height: 1)
                    .accessibilityHidden(true)
            }
            link(row, in: snapshot)
        }
        .padding(.leading, CGFloat(row.indentationLevel) * Self.indentationStep)
    }

    /// The control that opens and closes a row's subtree.
    ///
    /// Its own button, beside the link rather than wrapped around it, with a 44 pt tap target and
    /// an explicit content shape so the whole target is hittable and not only the glyph. The
    /// rotation is what distinguishes an open row from a closed one and both from a leaf; the
    /// animation comes from ``ViewHierarchyViewModel/toggleExpansion(_:)``, which animates the rows
    /// the toggle reveals in the same transaction.
    private func disclosure(for row: ViewHierarchyViewModel.Row) -> some View {
        Button {
            viewModel.toggleExpansion(row.node)
        } label: {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                .frame(width: Self.disclosureWidth, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isExpanded ? localized("Collapse") : localized("Expand"))
        .accessibilityValue(row.className)
    }

    /// The search results, or a line naming the query when nothing matched.
    @ViewBuilder
    private func searchResults(in snapshot: ViewHierarchySnapshot) -> some View {
        if viewModel.matchRows.isEmpty {
            noSearchResults
        } else {
            ForEach(viewModel.matchRows) { match in
                searchRow(match, in: snapshot)
            }
        }
    }

    /// One search result: the ancestor path above the row it found.
    ///
    /// Without the path a hit is a class name with no address — `UILabel` says nothing about which
    /// `UILabel`. The path is truncated at its head, so the ancestors nearest the match, which are
    /// the ones that identify it, survive on a narrow screen. Results are a flat list, so no row
    /// here carries a disclosure control.
    private func searchRow(_ match: ViewHierarchyViewModel.MatchRow,
                           in snapshot: ViewHierarchySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !match.path.isEmpty {
                Text(match.path.joined(separator: " › "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            link(match.row, in: snapshot)
        }
    }

    /// A row that pushes the node's detail page.
    private func link(_ row: ViewHierarchyViewModel.Row,
                      in snapshot: ViewHierarchySnapshot) -> some View {
        NavigationLink {
            ViewDetailView(node: row.node,
                           snapshot: snapshot,
                           windowBounds: viewModel.windowBounds)
        } label: {
            label(for: row)
        }
    }

    /// A row's contents: the class name, its size, and its badges.
    ///
    /// The badge words are folded into one accessibility label rather than left as separate
    /// elements, so the row reads as "UILabel, 200 × 20, hidden" in a single pass instead of making
    /// VoiceOver walk three lozenges. The label is the link's, and is deliberately nothing like the
    /// disclosure button's "Expand" / "Collapse".
    private func label(for row: ViewHierarchyViewModel.Row) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.className)
                Text(row.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ForEach(row.badges) { badge in
                lozenge(badge)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// The small lozenge one badge is drawn as, matching the network log's own badges.
    private func lozenge(_ badge: ViewHierarchyViewModel.Badge) -> some View {
        Text(badge.word.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(colour(for: badge), in: RoundedRectangle(cornerRadius: 4))
    }

    /// The colour a badge is drawn in.
    private func colour(for badge: ViewHierarchyViewModel.Badge) -> Color {
        switch badge {
        case .hidden: return .gray
        case .zeroSize: return .orange
        case .offScreen: return .purple
        }
    }

    /// Shown when a search matches nothing.
    ///
    /// Names the query rather than using `ContentUnavailableView.search(text:)` the way the Cookie
    /// Browser does: that type is iOS 17, and this feature's localisation fragment already carries
    /// a key that names the query, so one branch serves both iOS 16 and 17 and says the same thing
    /// on each.
    private var noSearchResults: some View {
        Text(localized("No views match \(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))"))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    NavigationStack {
        ViewHierarchyView()
    }
}
#endif
