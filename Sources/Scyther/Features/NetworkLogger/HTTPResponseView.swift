//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import SwiftUI

struct HTTPRequestView: View {
    @StateObject var viewModel: HTTPRequestViewModel
    private let searchTerm: String?
    
    init(request: HTTPRequest, searchTerm: String? = nil) {
        _viewModel = StateObject(wrappedValue: HTTPRequestViewModel(request: request))
        self.searchTerm = searchTerm
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(viewModel.accentColor))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(viewModel.method)
                        .bold()
                    Text(viewModel.responseCode)
                        .foregroundStyle(Color(viewModel.accentColor))
                        .frame(maxHeight: .infinity, alignment: .top)
                    Text(viewModel.requestTime)
                        .font(.caption)
                        .foregroundStyle(Color.gray)
                }
                if viewModel.isGraphQL {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(viewModel.operationName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                            if let badge = viewModel.operationBadgeText {
                                lozenge(badge, colour: viewModel.operationBadgeColor)
                            }
                            mockedBadge
                            overriddenBadge
                            replayBadge
                            heldBadge
                        }
                        HighlightingText(viewModel.url, substring: searchTerm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            mockedBadge
                            overriddenBadge
                            replayBadge
                            heldBadge
                        }
                        HighlightingText(viewModel.url, substring: searchTerm)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// The badge marking a row whose response an override synthesised instead of the network.
    ///
    /// Renders nothing when the response came off the wire, so both branches of `body` can place
    /// it unconditionally rather than each repeating the same `if`.
    ///
    /// Pink rather than orange so a synthesised response cannot be mistaken for anything else in
    /// the log: orange already marks a GraphQL mutation, and no other lozenge in the list uses
    /// pink. A response that did not come off the wire is the single most misleading thing the
    /// log can show, so it gets the colour nothing else competes with.
    @ViewBuilder
    private var mockedBadge: some View {
        if viewModel.wasStubbed {
            lozenge(localized("MOCKED"), colour: .pink)
        }
    }

    /// The badge marking a row the developer resent from the replay editor.
    ///
    /// Renders nothing for traffic the app itself made, so both branches of `body` can place it
    /// unconditionally.
    ///
    /// Teal rather than the purple the plan named: purple is already the lozenge a GraphQL
    /// subscription wears, and these two can appear on the same row. The mocked badge earned pink
    /// by being the one colour nothing else in the log competes for, and a replay is told apart
    /// the same way.
    @ViewBuilder
    private var replayBadge: some View {
        if viewModel.isReplay {
            lozenge(localized("REPLAY"), colour: .teal)
        }
    }

    /// The badge marking a row a breakpoint held on its way through.
    ///
    /// Renders nothing for traffic that was never held, so both branches of `body` can place it
    /// unconditionally.
    ///
    /// Indigo, for the reason pink marks a mock and teal marks a replay: it is a colour nothing
    /// else in this list wears, and all three can appear on the same row. A held request is a row
    /// the developer had their hands on, which is exactly as misleading as a mocked one if the log
    /// does not say so.
    @ViewBuilder
    private var heldBadge: some View {
        if viewModel.wasHeld {
            lozenge(localized("HELD"), colour: .indigo)
        }
    }

    /// The badge marking a row an override shaped without answering.
    ///
    /// Brown, on the same reasoning as the other three: a colour nothing else in this list wears,
    /// so all four can sit on one row without any of them being mistaken for another.
    @ViewBuilder
    private var overriddenBadge: some View {
        if viewModel.wasOverridden {
            lozenge(localized("OVERRIDDEN"), colour: .brown)
        }
    }

    /// The small uppercase lozenge used for both the GraphQL operation type and the mocked badge.
    ///
    /// - Parameters:
    ///   - text: The badge text, already uppercased by its source.
    ///   - colour: The lozenge fill.
    /// - Returns: The badge.
    private func lozenge(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(colour, in: RoundedRectangle(cornerRadius: 4))
    }
}

class HTTPRequestViewModel: ObservableObject {
    let request: HTTPRequest
    
    init(request: HTTPRequest) {
        self.request = request
    }
    
    var method: String {
        request.requestMethod ?? "-"
    }
    
    var responseCode: String {
        "\(request.responseCode ?? 0)"
    }
    
    var requestTime: String {
        String(format: "%.0fms", request.requestDuration ?? 0)
    }
    
    var url: String {
        request.requestURL ?? "-"
    }
    
    var accentColor: UIColor {
        switch request.responseCode ?? 0 {
        case ..<1:
            return .systemGray
        case ..<100:
            return .systemBlue
        case ..<200:
            return .systemOrange
        case ..<300:
            return .systemGreen
        case ..<400:
            return .systemPurple
        case ..<600:
            return .systemRed
        default:
            return .systemGray
        }
    }

    /// Whether the underlying request is a GraphQL operation.
    var isGraphQL: Bool {
        request.isGraphQL
    }

    /// The GraphQL operation name, or `"-"` when unavailable.
    var operationName: String {
        request.graphQLOperationName ?? "-"
    }

    /// The uppercased badge text for the operation type, or `nil` (e.g. batched requests).
    var operationBadgeText: String? {
        request.graphQLOperationType?.badgeText
    }

    /// Whether the response was synthesised by a request override rather than received from the
    /// network. Drives the `MOCKED` badge on the row.
    var wasStubbed: Bool {
        request.wasStubbed
    }

    /// Whether this request was resent from the replay editor rather than made by the app.
    /// Drives the `REPLAY` badge on the row.
    var isReplay: Bool {
        request.replayOfID != nil
    }

    /// Whether a breakpoint held this exchange on its way through. Drives the `HELD` badge.
    var wasHeld: Bool {
        !request.breakpointNames.isEmpty
    }

    /// Whether an override shaped this request without answering it. Drives the `OVERRIDDEN` badge.
    ///
    /// A stub already says so with `MOCKED`, so this is the other case: a header rewrite or a
    /// network condition applied to a request that still went out to the network. Without it, a
    /// request whose `Authorization` header we swapped, or which a condition made slow or made
    /// fail, is indistinguishable in the list from traffic nobody touched — which is the same lie
    /// the other three badges exist to prevent.
    var wasOverridden: Bool {
        !request.wasStubbed && !request.appliedRuleNames.isEmpty
    }

    /// The lozenge colour for the operation type.
    var operationBadgeColor: Color {
        switch request.graphQLOperationType {
        case .query: return .green
        case .mutation: return .orange
        case .subscription: return .purple
        case .none: return .secondary
        }
    }
}
