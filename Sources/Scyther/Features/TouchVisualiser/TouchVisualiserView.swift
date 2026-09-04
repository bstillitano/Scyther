//
//  TouchVisualiserView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 20/12/2025.
//

import SwiftUI

/// A SwiftUI view for configuring touch visualization settings.
///
/// This view provides toggles to:
/// - Enable/disable touch visualization
/// - Show touch duration labels
/// - Show touch radius scaling
/// - Enable console logging of touches
///
/// The touch visualiser displays visual indicators on screen wherever touches occur,
/// which is useful for debugging touch interactions and creating demonstrations.
struct TouchVisualiserView: View {
    @StateObject private var viewModel = TouchVisualiserViewModel()

    var body: some View {
        List {
            Section {
                Toggle(localized("Show Screen Touches"), isOn: $viewModel.visualiseTouches)

                if viewModel.visualiseTouches {
                    Toggle(localized("Show Touch Duration"), isOn: $viewModel.showTouchDuration)
                    Toggle(localized("Show Touch Radius"), isOn: $viewModel.showTouchRadius)
                    Toggle(localized("Log Screen Touches"), isOn: $viewModel.loggingEnabled)
                }
            }
        }
        .navigationTitle(localized("Visualise Touches"))
        .animation(.default, value: viewModel.visualiseTouches)
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}

#Preview {
    NavigationStack {
        TouchVisualiserView()
    }
}
