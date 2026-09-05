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
                        }
                        HighlightingText(viewModel.url, substring: searchTerm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        mockedBadge
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
    @ViewBuilder
    private var mockedBadge: some View {
        if viewModel.wasStubbed {
            lozenge(localized("MOCKED"), colour: .orange)
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
