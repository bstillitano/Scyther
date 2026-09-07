//
//  WaterfallView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Charts
import SwiftUI
import UIKit

/// Every logged request as a bar on one shared axis, oldest at the top.
///
/// Reached from the **See all** button in the Waterfall section of ``TrafficStatsView``. It is the
/// same chart that section draws — the bars, the colours, the outcomes, the ruler and the legend
/// all come from ``WaterfallChartStyle`` — given the room to show the whole log instead of the
/// most recent forty, and made tappable so a bar leads to the request behind it.
///
/// Three things about the layout are deliberate and load-bearing. The rows are a `LazyVStack`, so
/// a log holding thousands of captures only ever builds the handful of charts on screen. The
/// ruler is a pinned section header: a waterfall whose axis scrolls away stops being readable at
/// exactly the moment the reader has scrolled far enough to need it. And the whole thing is drawn
/// inside an inset grouped card, because a `ScrollView` gets none of the chrome a `List` gives the
/// section for free, and without it the same chart reads as a different component.
///
/// ## Usage
/// ```swift
/// NavigationLink(localized("See all")) {
///     WaterfallView(logs: logs)
/// }
/// ```
struct WaterfallView: View {
    /// The network log this page is drawing. Its filtered array is the input, so the page follows
    /// the log's search and filter chips the way the rest of the stats screen does.
    @ObservedObject private var logs: NetworkLogsViewModel

    /// The page's own view model.
    @StateObject private var viewModel: WaterfallViewModel

    /// Creates the page.
    ///
    /// - Parameter logs: The network log view model whose filtered requests are drawn.
    init(logs: NetworkLogsViewModel) {
        self.logs = logs
        _viewModel = StateObject(wrappedValue: WaterfallViewModel(requests: logs.requests))
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                timeline
            }
        }
        // The ground the card sits on, which is what a grouped List paints behind its sections.
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(localized("Waterfall"))
        .navigationBarTitleDisplayMode(.inline)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
        .onChange(of: logRevision) { _ in
            viewModel.update(requests: logs.requests)
        }
    }

    /// What the page watches the log for.
    ///
    /// The filtered count and the unfiltered count together, matching
    /// ``TrafficStatsView``: with a filter active, new traffic the filter excludes moves the
    /// unfiltered count only, and a page watching the filtered count alone would sit still while
    /// the screen it was opened from updated.
    private var logRevision: [Int] { [logs.requests.count, logs.totalRequestCount] }

    /// The bars, under a pinned ruler, inside the grouped card.
    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(viewModel.rows) { row in
                        NavigationLink {
                            LogDetailsView(httpRequest: row.request)
                        } label: {
                            WaterfallRowView(row: row, upperBound: viewModel.upperBound)
                        }
                        // Plain, because the row is a chart: the automatic link style would
                        // tint the bar's label and its duration in the accent colour, and the
                        // two surfaces would no longer look like the same chart.
                        .buttonStyle(.plain)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        // The last row closes the card. Asking the array rather than enumerating
                        // it keeps this O(1) per row, so a thousand-row log does not pay for the
                        // corner treatment on every redraw.
                        .clipShape(
                            WaterfallCardShape(
                                corners: row.id == viewModel.rows.last?.id
                                    ? [.bottomLeft, .bottomRight]
                                    : [],
                                radius: WaterfallChartStyle.cardCornerRadius
                            )
                        )
                        .padding(.horizontal, WaterfallChartStyle.cardInset)
                    }
                    Text(viewModel.caption)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        // Aligned with the card's content rather than its edge, the way a grouped
                        // List aligns a section footer.
                        .padding(
                            .horizontal,
                            WaterfallChartStyle.cardInset + WaterfallChartStyle.cardContentPadding
                        )
                        .padding(.vertical, 12)
                } header: {
                    WaterfallRulerView(upperBound: viewModel.upperBound)
                }
            }
        }
    }

    /// The placeholder shown for a log with nothing in it.
    @ViewBuilder
    private var emptyState: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                localized("No Traffic Captured"),
                systemImage: "chart.bar.xaxis",
                description: Text(
                    localized("Every request that has been logged appears here as a bar on one shared axis.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Traffic Captured"))
                    .font(.headline)
                Text(localized("Every request that has been logged appears here as a bar on one shared axis."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// One request's row on the full-log waterfall.
///
/// A chart of exactly one bar, with the name drawn beside it rather than by the chart's own y
/// axis. Charts sizes a leading axis to the labels it is given, so a per-row axis would be a
/// different width on every row and no two bars would start at the same x — which would quietly
/// destroy the only claim the chart makes, that bars which overlap were in flight together. A
/// fixed label column keeps every plot the same width, and therefore the axis genuinely shared.
private struct WaterfallRowView: View {
    /// The row to draw.
    let row: WaterfallViewModel.Row

    /// The far end of the shared axis, identical for every row on the page.
    let upperBound: Double

    var body: some View {
        HStack(spacing: WaterfallChartStyle.labelColumnSpacing) {
            Text(row.label)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.secondary)
                .frame(width: WaterfallChartStyle.labelColumnWidth, alignment: .trailing)
            Chart {
                WaterfallChartStyle.bar(id: row.id, entry: row.entry, upperBound: upperBound)
            }
            .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
            .chartXScale(domain: 0...upperBound)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: WaterfallChartStyle.barHeight)
        }
        .padding(.horizontal, WaterfallChartStyle.cardContentPadding)
        // The whole row is the target, not just the bar: a two millisecond request is a couple of
        // points wide and would otherwise be unhittable even though it is now visible.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// What VoiceOver reads for the row.
    ///
    /// The bar itself conveys length by width, which is nothing to a screen reader, so the name,
    /// the outcome and the duration are spoken instead.
    private var accessibilityLabel: String {
        [
            row.label,
            WaterfallChartStyle.outcomeTitle(for: row.entry),
            WaterfallChartStyle.valueLabel(for: row.entry),
        ].joined(separator: ", ") // scyther:unlocalised separator between localised parts
    }
}

/// The legend and the seconds ruler, pinned to the top of the page as the head of the card.
///
/// Both are drawn by Charts rather than by hand, so they are the same legend and the same ruler
/// the Traffic Stats section shows. They are two charts rather than one, and that split is the
/// fix for a real defect: sharing a chart put the legend inside the label column's offset, where
/// it had about a third less width than the section gives it and wrapped "Stubbed" onto a second
/// line. The legend now spans the card's full content width, exactly as the section's does, and
/// only the ruler is inset to line up with the bars — so it still wraps if the reader's text size
/// genuinely needs it to, and not before.
///
/// In each chart the zero-width marks exist only to give Charts something to derive its output
/// from, and the plot they sit in is collapsed to a point.
private struct WaterfallRulerView: View {
    /// The far end of the shared axis.
    let upperBound: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            legend
            HStack(spacing: WaterfallChartStyle.labelColumnSpacing) {
                // Holds the same width the rows give their labels, so the ruler's ticks line up
                // with the bars underneath them.
                Color.clear
                    .frame(width: WaterfallChartStyle.labelColumnWidth, height: 1)
                ruler
            }
        }
        .padding(.horizontal, WaterfallChartStyle.cardContentPadding)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque and card-coloured, because the rows scroll underneath it and it is the top of
        // the same card they are in.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(
            WaterfallCardShape(
                corners: [.topLeft, .topRight],
                radius: WaterfallChartStyle.cardCornerRadius
            )
        )
        .padding(.horizontal, WaterfallChartStyle.cardInset)
    }

    /// What each colour means, at the card's full content width.
    private var legend: some View {
        Chart(WaterfallChartStyle.outcomeTitles, id: \.self) { title in
            BarMark(
                xStart: .value(localized("Start"), 0),
                xEnd: .value(localized("End"), 0),
                y: .value(localized("Request"), title),
                height: .fixed(0)
            )
            .foregroundStyle(by: .value(localized("Outcome"), title))
        }
        .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(position: .bottom, spacing: 0)
        .chartPlotStyle { plot in
            plot.frame(height: 1)
        }
        .frame(height: WaterfallChartStyle.legendHeight)
    }

    /// The seconds axis the bars below are measured against.
    private var ruler: some View {
        Chart {
            BarMark(
                xStart: .value(localized("Start"), 0),
                xEnd: .value(localized("End"), 0),
                y: .value(localized("Request"), ""),
                height: .fixed(0)
            )
            .foregroundStyle(Color.clear)
        }
        .chartXScale(domain: 0...upperBound)
        .chartXAxisLabel(localized("Seconds"))
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.frame(height: 1)
        }
        .frame(height: WaterfallChartStyle.rulerHeight)
    }
}

/// A rectangle with only some of its corners rounded.
///
/// `UnevenRoundedRectangle` does this in one line, but it is iOS 17 and Scyther's floor is iOS 16.
/// The card needs it because it is assembled from its ends rather than drawn in one piece: the
/// pinned ruler rounds the top two corners, the last row rounds the bottom two, and every row
/// between them rounds none, so that a lazily built stack of rows still reads as one block. A
/// single background behind the whole stack would be simpler and would also make the stack
/// eager, which is the one thing a page built for thousands of rows cannot afford.
struct WaterfallCardShape: Shape {
    /// Which corners to round. Empty for a row in the middle of the card.
    let corners: UIRectCorner

    /// How far the rounded corners are cut, in points.
    let radius: CGFloat

    /// Builds the shape.
    ///
    /// - Parameter rect: The rectangle to fill.
    /// - Returns: The path, which is `rect` itself when no corner is rounded — cheaper than
    ///   asking UIKit for a bezier that would come back square anyway, and it is the case almost
    ///   every row on the page takes.
    func path(in rect: CGRect) -> Path {
        guard !corners.isEmpty else { return Path(rect) }
        return Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
        )
    }
}
