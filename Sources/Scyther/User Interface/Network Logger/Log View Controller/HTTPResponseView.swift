//
//  File.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import ScytherUI
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
                HighlightingText(viewModel.url, substring: searchTerm)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .frame(alignment: .leading)
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
}
