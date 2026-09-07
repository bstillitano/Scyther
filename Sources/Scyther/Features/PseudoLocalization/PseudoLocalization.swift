//
//  PseudoLocalization.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

#if !os(macOS)
import UIKit

/// A singleton manager for pseudo-localisation: seeing whether an interface survives translation
/// without shipping a single translated string.
///
/// Four independent modes, each persisted in `UserDefaults.scyther` and off by default:
///
/// - ``accented`` swaps Latin letters for accented look-alikes, so anything still rendering as
///   plain ASCII was never localised.
/// - ``lengthened`` pads strings to roughly 135%, the expansion German and Finnish bring, so
///   clipping and truncation appear before a translator's work does.
/// - ``rightToLeft`` forces RTL layout in Scyther's own interface, which catches hard-coded
///   leading/trailing assumptions in it.
/// - ``showsKeys`` renders the catalog key instead of its translation.
///
/// A fifth switch, ``showsBoundaries``, is a setting *about* those rather than a fifth peer of
/// them: it keeps the `[` and `]` around a lengthened string, transforms nothing on its own, and
/// is the one switch that is **on** unless a developer has turned it off.
///
/// ## What this can and cannot reach
///
/// Every string in Scyther's own interface goes through ``localized(_:comment:override:)``, so the
/// text modes always apply there in full. Reaching the *host app's* strings is a different and
/// much weaker proposition, and the honest answer depends on how the app loads them:
///
/// - `NSLocalizedString` funnels through `Bundle.localizedString(forKey:value:table:)`, an
///   Objective-C method that ``PseudoLocalizationHostHook`` can and does hook.
/// - `String(localized:)`, `LocalizedStringResource` and SwiftUI's `Text("some key")` do **not**.
///   Measured, not assumed: with that method hooked, resolving a string through each of those
///   paths — and rendering a `Text` all the way to pixels with `ImageRenderer` — never once
///   reached the hook. Foundation's Swift-native lookup does not go through `NSBundle` at all,
///   and no other `NSBundle` selector (`localizedStringForKey:value:table:localizations:`
///   included) sees them either.
///
/// So on a UIKit or `NSLocalizedString`-based app the text modes apply broadly; on a SwiftUI app
/// using `Text("…")` they apply to Scyther's own interface and nothing else.
/// ``rightToLeft`` has a different shape rather than a different limit. It changes no text, so it
/// does not care how the host loads its copy at all: Scyther's own interface mirrors immediately,
/// in both directions, and the host app mirrors on its **next launch** — UIKit and SwiftUI alike,
/// since the mechanism is the pair of defaults keys iOS resolves at launch rather than anything
/// applied to a view. See ``PseudoLocalizationLayout``.
///
/// ```swift
/// PseudoLocalization.instance.accented = true
/// PseudoLocalization.instance.lengthened = true
/// ```
///
/// ## Topics
/// ### Getting the Shared Instance
/// - ``instance``
///
/// ### Configuration
/// - ``accented``
/// - ``lengthened``
/// - ``rightToLeft``
/// - ``showsKeys``
/// - ``showsBoundaries``
/// - ``reset()``
///
/// ### Effects
/// - ``applyEffects(isTestCase:isAppStore:)``
///
/// ### Resolution
/// - ``activeModes``
/// - ``storedModes``
/// - ``resolvedModes(stored:isAppStore:)``
/// - ``canAffectHostApp(isTestCase:isAppStore:)``
///
/// ### Notifications
/// - ``ModesChangedNotification``
///
/// ### UserDefaults Keys
/// - ``AccentedDefaultsKey``
/// - ``LengthenedDefaultsKey``
/// - ``RightToLeftDefaultsKey``
/// - ``ShowsKeysDefaultsKey``
/// - ``ShowsBoundariesDefaultsKey``
@MainActor
internal final class PseudoLocalization: @unchecked Sendable {
    // MARK: - Static Data (nonisolated for cross-thread access)

    /// Posted on the main actor whenever the switches change, so SwiftUI views that are already on
    /// screen can re-render.
    ///
    /// Needed only by ``PseudoLocalizationMode/rightToLeft``, and only because SwiftUI takes its
    /// layout direction from the environment: ``MenuView`` installs that value, and without a
    /// signal it would go on installing the old one until something else happened to invalidate
    /// it — which, for a menu the developer is looking at while flicking the switch, is never. The
    /// text modes need nothing like this, because every string is re-resolved through
    /// ``localized(_:comment:)`` on the next render anyway.
    ///
    /// A notification rather than `ObservableObject`, matching ``InterfaceToolkit``'s existing
    /// change notifications, so this type stays a plain settings singleton readable from any
    /// thread rather than acquiring a publisher and an isolation story to go with it.
    nonisolated static let ModesChangedNotification = NSNotification.Name("Scyther.PseudoLocalization.ModesChanged")

    /// UserDefaults key for storing whether accented glyphs are substituted.
    nonisolated static let AccentedDefaultsKey: String = "Scyther_pseudo_localization_accented"

    /// UserDefaults key for storing whether strings are padded.
    nonisolated static let LengthenedDefaultsKey: String = "Scyther_pseudo_localization_lengthened"

    /// UserDefaults key for storing whether layout is forced right-to-left.
    nonisolated static let RightToLeftDefaultsKey: String = "Scyther_pseudo_localization_right_to_left"

    /// UserDefaults key for storing whether catalog keys are shown in place of translations.
    nonisolated static let ShowsKeysDefaultsKey: String = "Scyther_pseudo_localization_show_keys"

    /// UserDefaults key for storing whether transformed strings keep their delimiters.
    nonisolated static let ShowsBoundariesDefaultsKey: String = "Scyther_pseudo_localization_show_boundaries"

    /// Where the switches are persisted.
    ///
    /// Injected rather than read from `UserDefaults.scyther` at each call site so a test can hand
    /// in a throwaway suite and assert on persistence without writing to — or having to clean up
    /// after itself in — the suite a developer's real settings live in.
    ///
    /// `nonisolated(unsafe)` because `UserDefaults` is not `Sendable` but is documented as
    /// thread-safe, and the properties below are deliberately `nonisolated`: string resolution
    /// happens wherever a string is needed, and a main-actor hop per label would be a real cost
    /// on a screen with a hundred of them.
    nonisolated(unsafe) private let defaults: UserDefaults

    /// Creates a manager backed by a specific defaults store.
    ///
    /// - Parameter defaults: Where the switches are persisted. Defaults to `UserDefaults.scyther`.
    nonisolated init(defaults: UserDefaults = .scyther) {
        self.defaults = defaults
    }

    /// The shared singleton instance of `PseudoLocalization`.
    ///
    /// `nonisolated` unlike its siblings elsewhere in the toolkit, because the one caller that
    /// matters most is not on the main actor and must not hop to it:
    /// ``localized(_:comment:override:)`` resolves strings wherever they are needed, and a
    /// main-actor hop per label would put an `await` in front of every piece of copy in Scyther.
    nonisolated static let instance = PseudoLocalization()

    // MARK: - Configuration

    /// Whether Latin letters are replaced with accented look-alikes.
    ///
    /// The value is persisted to `UserDefaults.scyther` and restored on app launch.
    internal nonisolated var accented: Bool {
        get { defaults.bool(forKey: Self.AccentedDefaultsKey) }
        set {
            defaults.setValue(newValue, forKey: Self.AccentedDefaultsKey)
            synchronise()
        }
    }

    /// Whether strings are padded to roughly 135% of their length.
    ///
    /// The value is persisted to `UserDefaults.scyther` and restored on app launch.
    internal nonisolated var lengthened: Bool {
        get { defaults.bool(forKey: Self.LengthenedDefaultsKey) }
        set {
            defaults.setValue(newValue, forKey: Self.LengthenedDefaultsKey)
            synchronise()
        }
    }

    /// Whether the interface is forced into right-to-left layout.
    ///
    /// The value is persisted to `UserDefaults.scyther` and restored on app launch.
    internal nonisolated var rightToLeft: Bool {
        get { defaults.bool(forKey: Self.RightToLeftDefaultsKey) }
        set {
            defaults.setValue(newValue, forKey: Self.RightToLeftDefaultsKey)
            synchronise()
        }
    }

    /// Whether catalog keys are rendered in place of their translations.
    ///
    /// The value is persisted to `UserDefaults.scyther` and restored on app launch.
    internal nonisolated var showsKeys: Bool {
        get { defaults.bool(forKey: Self.ShowsKeysDefaultsKey) }
        set {
            defaults.setValue(newValue, forKey: Self.ShowsKeysDefaultsKey)
            synchronise()
        }
    }

    /// Whether a lengthened string keeps the `[` and `]` marking where it starts and ends.
    ///
    /// The one switch here that reads as `true` with nothing stored, which is why it cannot use
    /// `UserDefaults.bool(forKey:)` — that method answers absence with `false`, the opposite of
    /// what is wanted for a setting that ships on. It is the same read
    /// ``AccessibilityAudit/isEnabled(_:)`` does, for the same reason: an existing install where
    /// nothing has been written must keep behaving exactly as it did before the switch existed.
    ///
    /// On rather than off because the brackets are the diagnostic. The padding dots already say a
    /// string grew; only the closing bracket says whether the end of it was cut off, which is the
    /// thing ``lengthened`` exists to reveal. The switch is for the developer who has seen enough
    /// of them and wants the expansion without the punctuation.
    ///
    /// The value is persisted to `UserDefaults.scyther` and restored on app launch.
    internal nonisolated var showsBoundaries: Bool {
        get {
            guard let stored = defaults.object(forKey: Self.ShowsBoundariesDefaultsKey) as? Bool else { return true }
            return stored
        }
        set {
            defaults.setValue(newValue, forKey: Self.ShowsBoundariesDefaultsKey)
            synchronise()
        }
    }

    /// Switches every mode off and tears down the effects they installed.
    ///
    /// Exists as one call rather than four assignments so the settings screen's escape hatch — and
    /// anything recovering from a session left in an unreadable state — cannot half-succeed and
    /// leave, say, the host-app hook installed with no mode to justify it.
    ///
    /// ``showsBoundaries`` is restored to `true` rather than cleared to `false`, because "off" is
    /// not its shipped state. This is the button that puts the page back the way it was found; a
    /// developer who pressed it and then switched lengthening on again would otherwise get an
    /// unbracketed sample and no reason to connect it to a button they pressed a minute ago.
    internal nonisolated func reset() {
        defaults.setValue(false, forKey: Self.AccentedDefaultsKey)
        defaults.setValue(false, forKey: Self.LengthenedDefaultsKey)
        defaults.setValue(false, forKey: Self.RightToLeftDefaultsKey)
        defaults.setValue(false, forKey: Self.ShowsKeysDefaultsKey)
        defaults.setValue(true, forKey: Self.ShowsBoundariesDefaultsKey)
        synchronise()
    }

    // MARK: - Resolution

    /// The modes persisted in ``defaults``, before any environment gating.
    ///
    /// Separated from ``activeModes`` so the App Store guard can be tested as a pure function:
    /// `AppEnvironment.isAppStore` is unconditionally `false` in the test host, so a test going in
    /// through ``activeModes`` could never reach the branch that refuses.
    internal nonisolated var storedModes: PseudoLocalizationMode {
        var modes: PseudoLocalizationMode = []
        if accented { modes.insert(.accented) }
        if lengthened { modes.insert(.lengthened) }
        if rightToLeft { modes.insert(.rightToLeft) }
        if showsKeys { modes.insert(.showsKeys) }
        if showsBoundaries { modes.insert(.showsBoundaries) }
        return modes
    }

    /// The modes actually in force, which is nothing at all on an App Store build.
    ///
    /// Read on the hot path — once per string Scyther resolves — so it deliberately hits
    /// `UserDefaults` directly rather than maintaining a cached copy behind a lock. The suite is
    /// an in-memory dictionary after its first load, and the same trade is already made far more
    /// aggressively elsewhere in the toolkit: `UIView.refreshDebugBorders()` reads a `Bool` out of
    /// it for every view in the app on every layout pass.
    internal nonisolated var activeModes: PseudoLocalizationMode {
        Self.resolvedModes(stored: storedModes, isAppStore: AppEnvironment.isAppStore)
    }

    /// Whether persisted modes should be honoured, given the build they are running in.
    ///
    /// Scyther's belt-and-braces production guard, in the shape ``AccessibilityAudit`` already
    /// uses: `Scyther.start(allowProductionBuilds:)` returns early on an App Store build, but a
    /// switch left on in a TestFlight build and carried into a store build through the same
    /// preferences file would otherwise still pseudo-localise a shipping app.
    ///
    /// - Parameters:
    ///   - stored: The modes persisted in the defaults suite.
    ///   - isAppStore: Whether this is an App Store build, per ``AppEnvironment/isAppStore``.
    /// - Returns: `stored`, or the empty set on an App Store build.
    internal nonisolated static func resolvedModes(
        stored: PseudoLocalizationMode,
        isAppStore: Bool
    ) -> PseudoLocalizationMode {
        isAppStore ? [] : stored
    }

    /// Whether the effects that reach outside Scyther's own interface may be installed.
    ///
    /// Both of them mutate state the host app owns — a swizzle on `NSBundle`, and two keys in its
    /// standard `UserDefaults` — so they carry a stricter guard than the string transform does.
    /// Under XCTest there is no host app to pseudo-localise, and touching either would leak across
    /// into unrelated tests in the same process.
    ///
    /// ``PseudoLocalizationLayout/applyToHostApp(rightToLeft:isTestCase:isAppStore:systemDefaults:)``
    /// consults this before *setting* its keys and deliberately not before removing them; see there
    /// for why an App Store build clearing a stale key is the safe direction to err in.
    ///
    /// A pure function of two booleans for the same reason ``AccessibilityAudit/canAuditKeyWindow(isTestCase:isAppStore:)``
    /// is: neither input can be faked in the test host, so the refusing branches are unreachable
    /// from any test that goes in through the caller.
    ///
    /// - Parameters:
    ///   - isTestCase: Whether the process is running under XCTest, per ``AppEnvironment/isTestCase``.
    ///   - isAppStore: Whether this is an App Store build, per ``AppEnvironment/isAppStore``.
    /// - Returns: `true` only when the host app may be touched.
    internal nonisolated static func canAffectHostApp(isTestCase: Bool, isAppStore: Bool) -> Bool {
        !isTestCase && !isAppStore
    }

    // MARK: - Effects

    /// Brings the host-app hook, the host app's launch-time layout direction, and the views
    /// watching for a change, into line with the switches.
    ///
    /// Called from every setter rather than from the settings screen so the effects can never
    /// drift from what is persisted — including on the path that matters most, ``reset()``, whose
    /// whole job is to make an unreadable session readable again.
    ///
    /// Hops to the main actor because installing the hook and posting to observing views both have
    /// to happen there. The hop is why the setters can stay `nonisolated`, which is what lets the
    /// toggles be driven from a `Binding` without the view model having to await anything. It
    /// deliberately carries nothing across the hop; see ``applyEffects(isTestCase:isAppStore:)``
    /// for why that matters.
    private nonisolated func synchronise() {
        Task { @MainActor in self.applyEffects() }
    }

    /// Puts the host-app hook and the host app's forced layout direction into the state the
    /// *current* settings call for, and tells the views on screen that the modes have moved.
    ///
    /// The mode set is read here, on the main actor, rather than snapshotted by ``synchronise()``
    /// before it hops. That is the whole point of the split. The hops are unstructured `Task`s and
    /// the setters are `nonisolated`, so two changes in quick succession — a flurry of toggles, or
    /// ``reset()`` racing a `didSet` — can arrive in either order. With a snapshot, the loser of
    /// that race writes stale state and nothing re-syncs until the next toggle, which is how a
    /// developer ends up with the swizzle installed or right-to-left forced while every switch is
    /// persisted off: the feature cannot be turned off, which is the worst failure it has. Reading
    /// the settings at the moment they are applied makes every ordering converge on the same
    /// answer.
    ///
    /// - Parameters:
    ///   - isTestCase: Whether the process is running under XCTest, per ``AppEnvironment/isTestCase``.
    ///   - isAppStore: Whether this is an App Store build, per ``AppEnvironment/isAppStore``.
    @MainActor
    internal func applyEffects(
        isTestCase: Bool = AppEnvironment.isTestCase,
        isAppStore: Bool = AppEnvironment.isAppStore
    ) {
        let modes = activeModes
        PseudoLocalizationHostHook.shared.setEnabled(
            !modes.intersection(.textAffecting).isEmpty,
            isTestCase: isTestCase,
            isAppStore: isAppStore
        )
        PseudoLocalizationLayout.applyToHostApp(
            rightToLeft: modes.contains(.rightToLeft),
            isTestCase: isTestCase,
            isAppStore: isAppStore
        )
        NotificationCenter.default.post(name: Self.ModesChangedNotification, object: nil)
    }

    /// Re-applies the persisted state at launch, so a session picks up where the last one left off.
    ///
    /// Called from `Scyther.start(allowProductionBuilds:)`. Without it, a developer who left a text
    /// mode on would find the host-app hook uninstalled after a relaunch while the switch still
    /// read as on — the feature silently doing nothing, which is the failure that is hardest to
    /// notice.
    internal static func setup() {
        instance.synchronise()
    }
}
#endif
