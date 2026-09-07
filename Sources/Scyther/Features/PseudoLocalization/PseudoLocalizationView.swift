//
//  PseudoLocalizationView.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import SwiftUI

/// The settings page for pseudo-localisation.
///
/// Four stock `Toggle`s in one `Section`, a fifth in a section of its own, a live sample of the
/// transformation, and a button that switches everything off.
///
/// Right to Left raises the same **Relaunch required** alert ``LanguageView`` raises, reusing its
/// title, its buttons and its ``ViewModel/quitApp()`` route so the two settings that only apply at
/// launch behave identically. Only the message differs: the language page can say Scyther's menu
/// has already switched, and this one cannot, because nothing changes here until a relaunch.
///
/// The fifth is separated deliberately. ``PseudoLocalizationMode/showsBoundaries`` is not a peer of
/// the other four — it switches nothing on, it changes how one of them renders, and it is the only
/// one that ships on — so listing it as a fifth equal would invite a developer to flick it looking
/// for an effect and find none.
///
/// Every string on this page is resolved through ``localizedChrome(_:comment:override:)`` rather
/// than ``localized(_:comment:override:)``. That is not a stylistic choice: with "Show keys" and
/// right-to-left both on, a page that pseudo-localised itself would render as a column of raw
/// catalog keys laid out backwards, and the switch to undo it would be among them. The sample row
/// exists so the page can still show what the modes do while remaining the one place they do not
/// apply.
///
/// The exemption covers *text* only. Right to Left is a next-launch setting on every surface, so
/// this page does not flip while the switch is being flicked — and after a relaunch with the mode
/// on it is mirrored along with the rest of the app, deliberately, since plain English reads
/// perfectly well mirrored and insulating one screen would misrepresent what the mode does.
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
                        subtitle: localizedChrome("Mirrors the whole app on its next launch, to find hard-coded leading and trailing edges.")
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
                Toggle(isOn: $viewModel.showsBoundaries) {
                    label(
                        localizedChrome("Show Boundaries"),
                        subtitle: localizedChrome("Marks where each string starts and ends, so you can see when one has been cut off. Only shows up when another text mode is on.")
                    )
                }
            } header: {
                Text(localizedChrome("Boundaries"))
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
        .alert(localizedChrome("Relaunch required"), isPresented: $viewModel.showingRelaunchAlert) {
            Button(localizedChrome("Later"), role: .cancel) {}
            Button(localizedChrome("Quit App"), role: .destructive) {
                viewModel.quitApp()
            }
        } message: {
            Text(localizedChrome("Right to Left applies the next time the app launches — your app and Scyther's menu, UIKit and SwiftUI alike. Switching it off restores everything on the launch after that."))
        }
        .onFirstAppear {
            await viewModel.onFirstAppear()
        }
    }

    /// A two-line switch label: title above, explanation below.
    ///
    /// Matches the rest of the menu's two-line rows rather than pushing the explanation into a
    /// section footer, because every switch on this page needs its own explanation and a footer
    /// each would separate them from the sentences describing them.
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
