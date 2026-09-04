//
//  NetworkLogFilterBar.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI

/// A horizontally scrolling row of filter chips pinned above the network log list.
///
/// The row starts with an icon-only chip that opens ``NetworkLogAllFiltersSheet``, followed by
/// one chip per ``NetworkLogFilterDimension`` that opens ``NetworkLogFilterSheet`` for that
/// dimension. Every chip is ``NetworkLogFilterChip/height`` points tall. Active chips are drawn
/// with an accent-tinted capsule and white text, and show the selected value when there is exactly
/// one or "Title · N" when there are several. When any dimension is constrained a red "Clear" chip
/// appears at the end. Chips use Liquid Glass on iOS 26 and filled capsules on earlier releases.
struct NetworkLogFilterBar: View {
    /// The filter whose selections the chips reflect.
    let filter: NetworkLogFilter

    /// Supplies the text for each dimension chip. See ``NetworkLogsViewModel/chipTitle(for:)``.
    let chipTitle: (NetworkLogFilterDimension) -> String

    /// Called when the leading all-filters chip is tapped.
    let onSelectAll: () -> Void

    /// Called when a dimension chip is tapped.
    let onSelect: (NetworkLogFilterDimension) -> Void

    /// Called when the clear chip is tapped.
    let onClear: () -> Void

    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    chips
                }
            } else {
                chips
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            NetworkLogFilterChip(
                title: nil,
                systemImage: "slider.horizontal.3",
                style: filter.isActive ? .active : .inactive,
                accessibilityLabel: filter.isActive
                    ? localized("All filters, \(filter.totalSelectionCount) selected")
                    : localized("All filters"),
                namespace: namespace,
                action: onSelectAll
            )
            ForEach(NetworkLogFilterDimension.allCases) { dimension in
                let count = filter.selectionCount(for: dimension)
                NetworkLogFilterChip(
                    title: chipTitle(dimension),
                    systemImage: dimension.systemImage,
                    style: count > 0 ? .active : .inactive,
                    accessibilityLabel: count > 0 ? localized("\(dimension.title), \(count) selected") : dimension.title,
                    namespace: namespace,
                    action: { onSelect(dimension) }
                )
            }
            if filter.isActive {
                NetworkLogFilterChip(
                    title: localized("Clear"),
                    systemImage: "xmark",
                    style: .destructive,
                    accessibilityLabel: localized("Clear all filters"),
                    namespace: namespace,
                    action: onClear
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.snappy, value: filter.isActive)
    }
}

/// The visual state of a ``NetworkLogFilterChip``.
enum NetworkLogFilterChipStyle: Sendable {
    /// Plain glass with primary text; nothing selected.
    case inactive
    /// Accent-tinted capsule with white text; something selected.
    case active
    /// Red-tinted capsule with white text; the Clear action.
    case destructive

    /// The capsule tint, or `nil` for untinted glass.
    var tint: Color? {
        switch self {
        case .inactive: return nil
        case .active: return Color.accentColor
        case .destructive: return Color.red
        }
    }
}

/// A single capsule chip in ``NetworkLogFilterBar``.
///
/// Every chip is exactly ``height`` points tall. The chip's ``NetworkLogFilterChipStyle`` decides
/// whether the capsule is untinted glass, accent-tinted, or red, with white content on any tinted
/// capsule. A `nil` title renders an icon-only chip. The capsule is drawn as interactive Liquid
/// Glass on iOS 26 and a filled capsule on earlier releases.
struct NetworkLogFilterChip: View {
    /// The fixed height of every chip, in points.
    static let height: CGFloat = 40

    /// The chip text, or `nil` for an icon-only chip.
    let title: String?

    /// The SF Symbol shown before the title.
    let systemImage: String

    /// The visual state of the chip.
    let style: NetworkLogFilterChipStyle

    /// The label read by assistive technologies.
    let accessibilityLabel: String

    /// The glass namespace shared by every chip in the bar.
    let namespace: Namespace.ID

    /// Called when the chip is tapped.
    let action: () -> Void

    private var isTinted: Bool { style.tint != nil }

    private var glassID: String { title ?? systemImage }

    var body: some View {
        capsule(
            Button(action: action) {
                label
                    .padding(.horizontal, title == nil ? 20 : 16)
                    .frame(height: Self.height)
            }
            .buttonStyle(.plain)
        )
    }

    /// Wraps the button in the capsule background appropriate for the platform.
    @ViewBuilder
    private func capsule<Content: View>(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    style.tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(),
                    in: .capsule
                )
                .glassEffectID(glassID, in: namespace)
        } else {
            content
                .background(
                    Capsule().fill(style.tint ?? Color(uiColor: .secondarySystemFill))
                )
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            if let title {
                Text(title)
            }
        }
        .font(.subheadline.weight(isTinted ? .semibold : .regular))
        .foregroundStyle(isTinted ? Color.white : Color.primary)
        .lineLimit(1)
        .fixedSize()
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    var filter = NetworkLogFilter()
    filter.methods = ["GET", "POST"]
    return NetworkLogFilterBar(
        filter: filter,
        chipTitle: { $0.title },
        onSelectAll: {},
        onSelect: { _ in },
        onClear: {}
    )
}
