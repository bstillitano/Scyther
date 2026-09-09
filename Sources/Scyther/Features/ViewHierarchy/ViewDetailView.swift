//
//  ViewDetailView.swift
//  Scyther
//

#if !os(macOS)
import SwiftUI
import UIKit

/// Everything the inspector knows about one view, on one page.
///
/// The page opens with the two things a developer looks at first — what the view looks like, and
/// where on the screen it is — and then lists the numbers behind them. The picture and the map
/// answer different questions and neither substitutes for the other: a thumbnail of a white
/// square says nothing about whether it is off the bottom of the screen, and a green mark on an
/// outline says nothing about what is drawn inside it.
///
/// Every section below is a stock `List` `Section` of stock `LabeledContent` rows, and a section
/// with nothing to report is left out rather than shown empty.
struct ViewDetailView: View {
    @StateObject private var viewModel: ViewDetailViewModel

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - node: The selected node.
    ///   - snapshot: The snapshot it came from.
    ///   - windowBounds: The window space the node's frame is measured in.
    init(node: ViewNode, snapshot: ViewHierarchySnapshot, windowBounds: CGRect) {
        _viewModel = StateObject(wrappedValue: ViewDetailViewModel(node: node,
                                                                   snapshot: snapshot,
                                                                   windowBounds: windowBounds))
    }

    var body: some View {
        List {
            Section(localized("Where it is")) {
                HStack(alignment: .center, spacing: 16) {
                    thumbnail
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    positionMap
                }
                .frame(height: 140)
            }

            section(localized("Geometry"), fields: viewModel.geometry)
            section(localized("Appearance"), fields: viewModel.appearance)
            section(localized("Context"), fields: viewModel.context)
            section(localized("Behaviour"), fields: viewModel.behaviour)
        }
        .navigationTitle(viewModel.node.className)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    /// One section of labelled values, or nothing when the section has no fields.
    ///
    /// A section is empty only when every field in it needed the live view and that view has
    /// gone. An empty `Context` heading over nothing would read as "this view has no context";
    /// no heading reads as what it is.
    ///
    /// - Parameters:
    ///   - title: The localised section heading.
    ///   - fields: The rows.
    /// - Returns: The section, or an empty view.
    @ViewBuilder
    private func section(_ title: String, fields: [ViewDetailViewModel.DetailField]) -> some View {
        if !fields.isEmpty {
            Section(title) {
                ForEach(fields) { field in
                    row(field)
                }
            }
        }
    }

    /// One labelled value.
    ///
    /// `LabeledContent`'s value truncates to a single line by default, which is wrong for the
    /// longest thing on this page: a responder chain in a real navigation stack is eight class
    /// names joined by arrows, and it is the answer to "which screen is this from" — the reason
    /// the `Context` section exists at all. `LabeledContent`'s builder form takes a `Text` whose
    /// line limit this controls, so the value wraps instead of being cut off with no way to read
    /// the rest. Selection is on for the same reason: a class name or a hex colour read off this
    /// page is usually on its way into a search field.
    ///
    /// - Parameter field: The field to draw.
    /// - Returns: The row.
    private func row(_ field: ViewDetailViewModel.DetailField) -> some View {
        LabeledContent {
            Text(field.value)
                .lineLimit(nil)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(field.label)
        }
        .textSelection(.enabled)
    }

    /// The rendered view, or the reason there is no picture of it.
    ///
    /// Decorative, and hidden from VoiceOver: a rasterised view carries no information a screen
    /// reader can use, and the same facts are in the rows below in a form it can.
    ///
    /// Until the model has an answer the slot is a clear placeholder rather than nothing, for two
    /// reasons: the page must not flash "This view no longer exists" at a view that is perfectly
    /// alive, and an empty view contributes no width, which would draw the position map at full
    /// width for one frame and then shunt it to half.
    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnail = viewModel.thumbnail {
            switch thumbnail {
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            case .hidden:
                thumbnailMessage(localized("Nothing to show — this view is hidden"))
            case .zeroSize:
                thumbnailMessage(localized("Nothing to show — this view has zero size"))
            case .unavailable:
                thumbnailMessage(localized("This view no longer exists"))
            }
        } else {
            Color.clear
        }
    }

    /// The sentence shown in place of a picture.
    ///
    /// - Parameter message: The localised reason.
    /// - Returns: The centred message.
    private func thumbnailMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }

    /// Where the view sits on the screen: its frame, filled, on an outline of the window.
    ///
    /// A frame outside the window is drawn outside the outline rather than clamped to its edge,
    /// which is ``ViewPositionMap``'s decision and the reason this drawing is worth having. The
    /// outline does not fill the canvas, so a frame just past the fold has somewhere to be drawn
    /// — see ``ViewPositionMap/outlineInset``.
    ///
    /// A drawing reads as nothing to VoiceOver, so the frame it depicts is spoken instead. Its
    /// label is not the section's own heading, which VoiceOver has just read out.
    private var positionMap: some View {
        Canvas { context, size in
            let outline = ViewPositionMap.outlineRect(forWindowBounds: viewModel.windowBounds,
                                                      in: size)
            context.stroke(Path(outline), with: .color(.secondary), lineWidth: 1)

            let frame = ViewPositionMap.rect(for: viewModel.node.frameInWindow,
                                             windowBounds: viewModel.windowBounds,
                                             in: size)
            context.fill(Path(frame), with: .color(.green))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(localized("Position on screen"))
        .accessibilityValue(viewModel.frameSummary)
    }
}

/// A hierarchy for the preview to describe, held for the life of the process.
///
/// The snapshot's side table is weak by design, so a root built inside the `#Preview` closure
/// would be gone before `StateObject`'s autoclosure ran at first render, and the preview would
/// demonstrate "This view no longer exists" instead of the page. The same lifetime trap this
/// feature's test fixtures have to step around.
@MainActor
private enum ViewDetailPreviewFixture {
    /// The previewed hierarchy's root.
    static let root: UIView = {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let label = UILabel(frame: CGRect(x: 16, y: 120, width: 220, height: 44))
        label.text = "Preview label" // scyther:unlocalised sample content for the preview
        label.backgroundColor = .systemBlue
        root.addSubview(label)
        return root
    }()

    /// The walk of it.
    static let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: root.bounds)
}

#Preview {
    NavigationStack {
        ViewDetailView(node: ViewDetailPreviewFixture.snapshot.root.children[0],
                       snapshot: ViewDetailPreviewFixture.snapshot,
                       windowBounds: ViewDetailPreviewFixture.root.bounds)
    }
}
#endif
