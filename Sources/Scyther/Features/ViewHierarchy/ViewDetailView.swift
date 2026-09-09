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
                    LabeledContent(field.label, value: field.value)
                }
            }
        }
    }

    /// The rendered view, or the reason there is no picture of it.
    ///
    /// Decorative, and hidden from VoiceOver: a rasterised view carries no information a screen
    /// reader can use, and the same facts are in the rows below in a form it can.
    ///
    /// Nothing is drawn until ``ViewDetailViewModel/isLoaded`` is `true`, so the page never
    /// briefly claims a live view no longer exists.
    @ViewBuilder
    private var thumbnail: some View {
        if viewModel.isLoaded {
            switch viewModel.thumbnail {
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
    /// which is ``ViewPositionMap``'s decision and the reason this drawing is worth having.
    ///
    /// A drawing reads as nothing to VoiceOver, so the frame it depicts is spoken instead.
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
        .accessibilityLabel(localized("Where it is"))
        .accessibilityValue(viewModel.frameSummary)
    }
}

#Preview {
    let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let label = UILabel(frame: CGRect(x: 16, y: 120, width: 220, height: 44))
    label.text = "Preview label" // scyther:unlocalised sample content for the preview
    label.backgroundColor = .systemBlue
    root.addSubview(label)

    let snapshot = ViewHierarchyWalker.snapshot(of: root, windowBounds: root.bounds)
    return NavigationStack {
        ViewDetailView(node: snapshot.root.children[0],
                       snapshot: snapshot,
                       windowBounds: root.bounds)
    }
}
#endif
