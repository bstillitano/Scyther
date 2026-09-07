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
        _viewModel = StateObject(
            wrappedValue: WaterfallViewModel(
                requests: logs.requests,
                totalCount: logs.totalRequestCount
            )
        )
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
        // The array itself, not a count derived from it. Watching counts meant a request that
        // *completed* moved nothing the page was looking at, so its bar stayed orange and
        // stretched to a stale "now" until unrelated traffic happened to arrive — on a page whose
        // whole subject is when things started and finished.
        .onReceive(logs.$requests) { requests in
            viewModel.update(requests: requests, totalCount: logs.totalRequestCount)
        }
    }

    /// The bars, under a pinned ruler, inside the grouped card.
    ///
    /// Wrapped in a `GeometryReader` for one reason: every plot on the page — the ruler's and
    /// each row's — is framed to ``WaterfallChartStyle/plotWidth(inPageWidth:)`` of the width it
    /// reports. That is what makes a tick and the bar beneath it line up by construction rather
    /// than by two hand-matched stacks of insets, and it is what lets a bar know how many seconds
    /// a point is worth, which is what its minimum rendered width is expressed in.
    private var timeline: some View {
        GeometryReader { geometry in
            let plotWidth = WaterfallChartStyle.plotWidth(inPageWidth: geometry.size.width)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(viewModel.rows) { row in
                            NavigationLink {
                                LogDetailsView(httpRequest: row.request)
                            } label: {
                                WaterfallRowView(
                                    row: row,
                                    upperBound: viewModel.upperBound,
                                    plotWidth: plotWidth
                                )
                            }
                            // Plain, because the row is a chart: the automatic link style would
                            // tint the bar's label and its duration in the accent colour, and the
                            // two surfaces would no longer look like the same chart.
                            .buttonStyle(.plain)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(
                                WaterfallCardShape(
                                    corners: row.isLast ? [.bottomLeft, .bottomRight] : [],
                                    radius: WaterfallChartStyle.cardCornerRadius
                                )
                            )
                            .padding(.horizontal, WaterfallChartStyle.cardInset)
                        }
                        Text(viewModel.caption)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            // Aligned with the card's content rather than its edge, the way a
                            // grouped List aligns a section footer.
                            .padding(
                                .horizontal,
                                WaterfallChartStyle.cardInset + WaterfallChartStyle.cardContentPadding
                            )
                            .padding(.vertical, 12)
                    } header: {
                        WaterfallRulerView(upperBound: viewModel.upperBound, plotWidth: plotWidth)
                    }
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
                    localized("Bars appear once requests are logged. The page follows the log's search and filters, so it draws whatever the list is showing.")
                )
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(localized("No Traffic Captured"))
                    .font(.headline)
                Text(localized("Bars appear once requests are logged. The page follows the log's search and filters, so it draws whatever the list is showing."))
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
/// A chart of exactly one bar, at a constant height, with the name drawn beside it rather than by
/// the chart's own y axis.
///
/// The height is the whole reason the page is worth opening. A chart left to fill its container
/// divides the screen between however many rows there are, so twenty-two requests came out as
/// twenty-two thin bars on one screen — the same picture the preview already showed — and a
/// thousand would have been a thousand hairlines. Pinning the height makes the stack as tall as
/// the log is long and hands the scrolling back to the `ScrollView`.
///
/// The name is drawn outside the chart because Charts sizes a leading axis to the labels it is
/// given, so a per-row axis would be a different width on every row and no two bars would start
/// at the same x — which would quietly destroy the only claim the chart makes, that bars which
/// overlap were in flight together.
private struct WaterfallRowView: View {
    /// The row to draw.
    let row: WaterfallViewModel.Row

    /// The far end of the shared axis, identical for every row on the page.
    let upperBound: Double

    /// How wide the plot is, identical for every row and for the ruler above them.
    let plotWidth: CGFloat

    /// The row's height, scaled against the reader's text size.
    ///
    /// Scaled rather than constant because the label beside the bar grows with Dynamic Type; a
    /// constant height would clip it at exactly the sizes where it most needs to be legible.
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = WaterfallChartStyle.rowHeight

    var body: some View {
        HStack(spacing: WaterfallChartStyle.labelColumnSpacing) {
            Text(row.label)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.secondary)
                .frame(width: WaterfallChartStyle.labelColumnWidth, alignment: .trailing)
            Chart {
                WaterfallChartStyle.bar(
                    id: row.id,
                    entry: row.entry,
                    upperBound: upperBound,
                    plotWidth: plotWidth
                )
            }
            .chartForegroundStyleScale(WaterfallChartStyle.styleScale)
            .chartXScale(domain: 0...upperBound)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(width: plotWidth)
        }
        .frame(height: rowHeight)
        .padding(.horizontal, WaterfallChartStyle.cardContentPadding)
        // The whole row is the target, not just the bar: a request drawn at the minimum width is
        // a point across and would otherwise be unhittable even though it is now visible.
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
/// the preview section shows. They are two charts rather than one, and that split is the fix for a
/// real defect: sharing a chart put the legend inside the label column's offset, where it had
/// about a third less width than the preview gives it and wrapped "Stubbed" onto a second line.
/// The legend now spans the card's full content width, exactly as the preview's does, and only
/// the ruler is inset to line up with the bars.
///
/// Both heights are fixed — a header that resized as the reader scrolled would shift every bar
/// under it — but scaled against the reader's text size, because a constant height clips the tick
/// labels and a wrapped legend at the sizes where either would actually happen.
///
/// In each chart the zero-width marks exist only to give Charts something to derive its output
/// from, and the plot they sit in is collapsed to a point.
private struct WaterfallRulerView: View {
    /// The far end of the shared axis.
    let upperBound: Double

    /// How wide the plot is, identical to every row's below.
    let plotWidth: CGFloat

    /// The legend's height, scaled against the reader's text size.
    @ScaledMetric(relativeTo: .caption) private var legendHeight: CGFloat = WaterfallChartStyle.legendHeight

    /// The ruler's height, scaled against the reader's text size.
    @ScaledMetric(relativeTo: .caption) private var rulerHeight: CGFloat = WaterfallChartStyle.rulerHeight

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
        .frame(height: legendHeight)
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
        .frame(width: plotWidth, height: rulerHeight)
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
