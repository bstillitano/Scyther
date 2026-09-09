//
//  ViewHierarchyView.swift
//  Scyther
//

#if !os(macOS)
import SwiftUI
import UIKit

/// The view hierarchy inspector's tree page.
///
/// One snapshot of the key window, opened to its first two levels, with a `.searchable` field
/// over class names and the text views carry. Selecting any row pushes ``ViewDetailView``.
///
/// The tree is drawn as a **flat list of the currently visible rows** rather than as nested
/// `DisclosureGroup`s. Nesting would hand SwiftUI the indentation for free, but its indent grows
/// without limit, and a view forty levels down a real screen would have its class name pushed off
/// the right of a phone. Indenting each row explicitly is what lets ``ViewNode/indentationLevel(forDepth:)``
/// cap the indent at eight levels while the row keeps its true depth. Each parent row is still a
/// stock `DisclosureGroup` driven by ``ViewHierarchyViewModel/expansionBinding(for:)``, so the
/// chevron, its animation and its accessibility come from the framework; only where the children
/// are drawn differs.
struct ViewHierarchyView: View {
    @StateObject private var viewModel = ViewHierarchyViewModel()

    /// How far one level of depth indents a row.
    private static let indentationStep: CGFloat = 14

    var body: some View {
        List {
            if viewModel.hasNoKeyWindow {
                Section {
                    Text(localized("There is no key window to inspect right now."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if viewModel.isSearching {
                Section {
                    if viewModel.matches.isEmpty {
                        noSearchResults
                    } else {
                        ForEach(viewModel.matches, id: \.node.id) { match in
                            searchRow(for: match)
                        }
                    }
                } header: {
                    header
                }
            } else {
                Section {
                    ForEach(viewModel.visibleNodes) { node in
                        treeRow(for: node)
                    }
                } header: {
                    header
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: localized("Search classes and text"))
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

    /// One row of the tree: a `DisclosureGroup` when the node has children, a plain link when it
    /// does not, indented to its capped depth.
    @ViewBuilder
    private func treeRow(for node: ViewNode) -> some View {
        Group {
            if node.children.isEmpty {
                link(to: node)
            } else {
                DisclosureGroup(isExpanded: viewModel.expansionBinding(for: node)) {
                    // The children are rows of this same list, not content nested inside the
                    // group — see the type's own documentation for why the tree is flat.
                    EmptyView()
                } label: {
                    link(to: node)
                }
            }
        }
        .padding(.leading, indentation(for: node))
    }

    /// One search result: the ancestor path above the row it found.
    ///
    /// Without the path a hit is a class name with no address — `UILabel` says nothing about
    /// which `UILabel`. The path is truncated at its head, so the ancestors nearest the match,
    /// which are the ones that identify it, survive on a narrow screen.
    private func searchRow(for match: ViewNodeSearch.Match) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !match.path.isEmpty {
                Text(match.path.joined(separator: " › "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            link(to: match.node)
        }
    }

    /// A row that pushes the node's detail page.
    private func link(to node: ViewNode) -> some View {
        NavigationLink {
            if let snapshot = viewModel.snapshot {
                ViewDetailView(node: node,
                               snapshot: snapshot,
                               windowBounds: viewModel.windowBounds)
            }
        } label: {
            label(for: node)
        }
    }

    /// A row's contents: the class name, its size, and its badges.
    ///
    /// The badge words are folded into one accessibility label rather than left as separate
    /// elements, so the row reads as "UILabel, 200 × 20, hidden" in a single pass instead of
    /// making VoiceOver walk three lozenges.
    private func label(for node: ViewNode) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.className)
                Text(viewModel.sizeDescription(for: node))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ForEach(viewModel.badges(for: node)) { badge in
                lozenge(badge)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.accessibilityLabel(for: node))
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

    /// How far a row is indented, capped at ``ViewNode/maximumIndentationDepth``.
    private func indentation(for node: ViewNode) -> CGFloat {
        CGFloat(ViewNode.indentationLevel(forDepth: node.depth)) * Self.indentationStep
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
