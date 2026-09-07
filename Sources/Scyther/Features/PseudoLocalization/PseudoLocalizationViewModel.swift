//
//  PseudoLocalizationViewModel.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation
import SwiftUI

/// View model backing the pseudo-localisation settings page.
///
/// Mirrors the switches on ``PseudoLocalization`` into `@Published` properties so SwiftUI can
/// bind to them, and writes every change straight back through `didSet` — the pattern
/// ``GridOverlayViewModel`` uses, for the same reason: the singleton, not the view model, is the
/// source of truth, and a mode has to take effect the instant it is switched on rather than when
/// the page is dismissed.
///
/// ## Usage
///
/// ```swift
/// struct PseudoLocalizationView: View {
///     @StateObject private var viewModel = PseudoLocalizationViewModel()
///
///     var body: some View {
///         List {
///             Toggle(isOn: $viewModel.accented) { … }
///         }
///         .onFirstAppear { await viewModel.onFirstAppear() }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Lifecycle
/// - ``onFirstAppear()``
///
/// ### Modes
/// - ``accented``
/// - ``lengthened``
/// - ``rightToLeft``
/// - ``showsKeys``
///
/// ### Presentation
/// - ``showsBoundaries``
///
/// ### Sample
/// - ``sampleSource``
/// - ``sampleText``
///
/// ### Actions
/// - ``turnEverythingOff()``
/// - ``showingRelaunchAlert``
class PseudoLocalizationViewModel: ViewModel {
    /// Whether letters are replaced with accented look-alikes.
    @Published var accented: Bool = false {
        didSet {
            guard !isLoading else { return }
            PseudoLocalization.instance.accented = accented
        }
    }

    /// Whether strings are padded to roughly 135% of their length.
    @Published var lengthened: Bool = false {
        didSet {
            guard !isLoading else { return }
            PseudoLocalization.instance.lengthened = lengthened
        }
    }

    /// Whether the app is forced into right-to-left layout on its next launch.
    @Published var rightToLeft: Bool = false {
        didSet {
            guard !isLoading else { return }
            PseudoLocalization.instance.rightToLeft = rightToLeft
            showingRelaunchAlert = true
        }
    }

    /// Whether the "Relaunch required" alert is presented.
    ///
    /// The same alert ``LanguageViewModel`` raises, for the same reason: a setting that iOS reads
    /// once, while the process is starting, cannot show its effect in the session that changes it.
    ///
    /// Raised in **both** directions, unlike the language page's, which only raises it when a
    /// language is chosen. Switching right-to-left off is just as invisible as switching it on —
    /// the two keys are removed immediately and the running process goes on laying itself out the
    /// way it launched — and a developer who switches it off and sees nothing happen has exactly
    /// the confusion the alert exists to prevent.
    @Published var showingRelaunchAlert: Bool = false

    /// Whether catalog keys are rendered in place of their translations.
    @Published var showsKeys: Bool = false {
        didSet {
            guard !isLoading else { return }
            PseudoLocalization.instance.showsKeys = showsKeys
        }
    }

    /// Whether a lengthened string keeps the brackets marking where it starts and ends.
    ///
    /// Seeded to `true` rather than `false` like the others, so the first render of the page — the
    /// one drawn before ``loadSettings()`` has run — already shows the switch in the position it
    /// ships in, rather than flicking on a moment later in front of the developer.
    @Published var showsBoundaries: Bool = true {
        didSet {
            guard !isLoading else { return }
            PseudoLocalization.instance.showsBoundaries = showsBoundaries
        }
    }

    /// Suppresses the `didSet` write-back while the published properties are being seeded.
    ///
    /// Without it, ``loadSettings()`` assigning the persisted value back into each property would
    /// look identical to the developer flicking the switch, and would write four values and run
    /// ``PseudoLocalization/synchronise()`` four times on every appearance. Harmless in effect,
    /// but it would make the persisted state depend on how often the page was visited, which is
    /// exactly the kind of thing that is impossible to reason about later.
    private var isLoading = false

    /// The untransformed sample sentence.
    ///
    /// Resolved through ``localizedChrome(_:comment:override:)`` and transformed by hand below,
    /// rather than resolved through ``localized(_:comment:override:)`` and transformed implicitly.
    /// The difference matters when "Show keys" is on: this page is exempt from the transform, so
    /// going the implicit route would leave the sample the one row on the page that quietly did
    /// nothing.
    var sampleSource: String {
        localizedChrome("Save changes to your profile")
    }

    /// The sample sentence with the currently switched-on modes applied.
    ///
    /// Gives the developer somewhere to look that is guaranteed to demonstrate the effect, on the
    /// one page where the effect is deliberately switched off. Computed rather than stored so it
    /// re-evaluates whenever a `@Published` switch changes, with no bookkeeping to keep in step.
    var sampleText: String {
        var modes: PseudoLocalizationMode = []
        if accented { modes.insert(.accented) }
        if lengthened { modes.insert(.lengthened) }
        if showsKeys { modes.insert(.showsKeys) }
        if showsBoundaries { modes.insert(.showsBoundaries) }
        return PseudoLocalizationTransform.apply(
            to: sampleSource,
            key: "Save changes to your profile",
            modes: modes
        )
    }

    /// Loads the persisted switches on first appearance.
    override func onFirstAppear() async {
        await super.onFirstAppear()
        await loadSettings()
    }

    /// Seeds the published properties from ``PseudoLocalization/instance``.
    @MainActor
    private func loadSettings() async {
        isLoading = true
        accented = PseudoLocalization.instance.accented
        lengthened = PseudoLocalization.instance.lengthened
        rightToLeft = PseudoLocalization.instance.rightToLeft
        showsKeys = PseudoLocalization.instance.showsKeys
        showsBoundaries = PseudoLocalization.instance.showsBoundaries
        isLoading = false
    }

    /// Switches every mode off, in the singleton and in the UI.
    ///
    /// Goes through ``PseudoLocalization/reset()`` rather than assigning `false` to the published
    /// properties, so the effects are torn down in one pass instead of one per mode, and so a mode
    /// added later cannot be left behind by a screen that forgot to clear it.
    ///
    /// ``showsBoundaries`` goes back to `true` here, not `false`, because it mirrors what
    /// ``PseudoLocalization/reset()`` has just written: the button restores the shipped state, and
    /// the shipped state for the brackets is on.
    ///
    /// Raises the relaunch alert when right-to-left was on, since this is the other way to switch
    /// it off — and the way most likely to be reached by someone trying to put things back. The
    /// keys are already gone by then; what has not happened, and cannot until a relaunch, is the
    /// app laying itself out left to right again.
    @MainActor
    func turnEverythingOff() {
        let wasMirrored = rightToLeft
        PseudoLocalization.instance.reset()
        isLoading = true
        accented = false
        lengthened = false
        rightToLeft = false
        showsKeys = false
        showsBoundaries = true
        isLoading = false
        if wasMirrored { showingRelaunchAlert = true }
    }
}
