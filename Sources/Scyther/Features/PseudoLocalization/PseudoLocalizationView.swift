//
//  PseudoLocalizationView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import SwiftUI

/// The settings page for pseudo-localisation.
///
/// Four stock `Toggle`s in one `Section`, a live sample of the transformation, and a button that
/// switches everything off.
///
/// Every string on this page is resolved through ``localizedChrome(_:comment:override:)`` rather
/// than ``localized(_:comment:override:)``. That is not a stylistic choice: with "Show keys" and
/// right-to-left both on, a page that pseudo-localised itself would render as a column of raw
/// catalog keys laid out backwards, and the switch to undo it would be among them. The sample row
/// exists so the page can still show what the modes do while remaining the one place they do not
/// apply.
///
/// The exemption covers *text* only. This page installs the forced layout direction on itself, the
/// same way ``MenuView`` does, so it mirrors along with the rest of Scyther — deliberately, since
/// plain English reads perfectly well mirrored and insulating this one screen would misrepresent
/// what the mode does. Installing it here as well as on ``MenuView`` is not redundant: it is what
/// makes the page the developer is looking at flip at the moment the switch moves, rather than
/// whenever SwiftUI next happens to hand it a fresh environment.
struct PseudoLocalizationView: View {
    /// The view model mirroring ``PseudoLocalization``'s switches.
    @StateObject private var viewModel = PseudoLocalizationViewModel()

    var body: some View {
        List {
            Section {
                Toggle(isOn: $viewModel.accented) {
                    label(
                        localizedChrome("Accented"),
                        subtitle: localizedChrome("Swaps letters for accented look-alikes. Anything still in plain ASCII was never localised.")
                    )
                }
                Toggle(isOn: $viewModel.lengthened) {
                    label(
                        localizedChrome("Lengthened"),
                        subtitle: localizedChrome("Pads text to about 135%, the expansion German and Finnish bring.")
                    )
                }
                Toggle(isOn: $viewModel.rightToLeft) {
                    label(
                        localizedChrome("Right to Left"),
                        subtitle: localizedChrome("Mirrors Scyther's interface now, and your app's UIKit views on its next launch. Your app's SwiftUI views are unaffected: Scyther cannot reach their environment.")
                    )
                }
                Toggle(isOn: $viewModel.showsKeys) {
                    label(
                        localizedChrome("Show Keys"),
                        subtitle: localizedChrome("Renders the catalog key instead of its translation.")
                    )
                }
            } header: {
                Text(localizedChrome("Modes"))
            } footer: {
                Text(localizedChrome("Modes combine. Showing keys wins over accenting and lengthening, so a key stays readable."))
            }

            Section {
                Text(viewModel.sampleText)
            } header: {
                Text(localizedChrome("Sample"))
            } footer: {
                Text(localizedChrome("One line of ordinary copy, with the modes you have switched on applied to it."))
            }

            Section {
                Button(role: .destructive) {
                    viewModel.turnEverythingOff()
                } label: {
                    Text(localizedChrome("Turn Everything Off"))
                }
            } footer: {
                Text(localizedChrome("This page is never pseudo-localised, so you can always switch the modes off again."))
            }

            Section {
                Text(localizedChrome("Scyther's own interface is always transformed. In your app, only strings loaded through NSLocalizedString are: String(localized:) and SwiftUI Text are resolved by Foundation without going through any hookable method."))
            } header: {
                Text(localizedChrome("Reach"))
            }
        }
        .navigationTitle(localizedChrome("Pseudo-localisation"))
        .environment(\.layoutDirection, PseudoLocalizationLayout.layoutDirection(
            forcingRightToLeft: viewModel.rightToLeft,
            languageIdentifier: LanguageOverride.shared.namingLocale.identifier
        ))
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    /// A two-line switch label: title above, explanation below.
    ///
    /// Matches the rest of the menu's two-line rows rather than pushing the explanation into a
    /// section footer, because each of the four modes needs its own explanation and four footers
    /// would separate every switch from the sentence describing it.
    ///
    /// - Parameters:
    ///   - title: The mode's name.
    ///   - subtitle: What the mode reveals.
    /// - Returns: The stacked label.
    private func label(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        PseudoLocalizationView()
    }
}
