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
/// The list is a native inline `Picker`, so it draws the standard selection checkmark and behaves
/// like the language list in Settings. Selecting a row applies immediately to Scyther's menu and
/// raises an alert explaining that the host app changes language on its next launch, with a
/// destructive Quit App action.
struct LanguageView: View {
    @StateObject private var viewModel: LanguageViewModel

    /// Creates the page.
    ///
    /// - Parameter viewModel: The view model, normally one editing the shared override. Deliberately
    ///   not defaulted: a default argument is evaluated eagerly wherever the initialiser is written,
    ///   so a `NavigationLink` destination would build a view model on every render of the row
    ///   rather than on navigation.
    init(viewModel: LanguageViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// The picker's selection, read from the override and written through
    /// ``LanguageViewModel/select(id:)`` so that choosing a row still applies the language and
    /// raises the relaunch alert.
    private var selection: Binding<String> {
        Binding(
            get: { viewModel.selectedRowID },
            set: { viewModel.select(id: $0) }
        )
    }

    var body: some View {
        List {
            Section(localized("Current")) {
                LabeledContent(localized("Language"), value: viewModel.currentLanguage)
                LabeledContent(localized("Region"), value: viewModel.currentRegion)
            }
            Section {
                Picker(localized("App language"), selection: selection) {
                    ForEach(viewModel.rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.nativeName)
                            Text(row.localizedName)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        .tag(row.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
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
