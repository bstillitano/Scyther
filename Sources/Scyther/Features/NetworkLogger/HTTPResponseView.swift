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
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(viewModel.operationBadgeColor, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        HighlightingText(viewModel.url, substring: searchTerm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HighlightingText(viewModel.url, substring: searchTerm)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .frame(alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
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
