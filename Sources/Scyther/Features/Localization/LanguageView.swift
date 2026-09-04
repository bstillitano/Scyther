//
//  LanguageView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/9/2026.
//

import SwiftUI

/// The Language page: shows the effective language and region, lists the host app's
/// localisations, and forces one via ``LanguageOverride``.
///
/// Selecting a row applies immediately to Scyther's menu and raises an alert explaining that the
/// host app changes language on its next launch, with a destructive Quit App action.
struct LanguageView: View {
    @StateObject private var viewModel: LanguageViewModel

    /// Creates the page.
    ///
    /// - Parameter viewModel: The view model. Defaults to one editing the shared override.
    init(viewModel: LanguageViewModel = LanguageViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section(localized("Current")) {
                LabeledContent(localized("Language"), value: viewModel.currentLanguage)
                LabeledContent(localized("Region"), value: viewModel.currentRegion)
            }
            Section {
                ForEach(viewModel.rows) { row in
                    Button {
                        viewModel.select(row)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.nativeName)
                                    .foregroundStyle(Color.primary)
                                Text(row.localizedName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if viewModel.isSelected(row) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(viewModel.isSelected(row) ? .isSelected : [])
                }
            } header: {
                Text(localized("App language"))
            } footer: {
                if viewModel.hasLanguages {
                    Text(localized("Changing the language applies to the whole app the next time it launches. Scyther's menu switches immediately."))
                } else {
                    Text(localized("This app declares no localisations beyond its base language, so there is nothing to switch to."))
                }
            }
            if viewModel.canReset {
                Section {
                    Button(role: .destructive) {
                        viewModel.reset()
                    } label: {
                        Text(localized("Reset Language Override"))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(localized("Language"))
        .alert(localized("Relaunch required"), isPresented: $viewModel.showingRelaunchAlert) {
            Button(localized("Later"), role: .cancel) {}
            Button(localized("Quit App"), role: .destructive) {
                viewModel.quitApp()
            }
        } message: {
            Text(localized("The app language changes the next time it launches. Scyther's menu has already switched."))
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }
}
