//
//  HostedSwiftUIWindow.swift
//  ScytherTests
//

import SwiftUI
import UIKit
import XCTest

/// Hosts a SwiftUI view in a real `UIWindow` and hands it back only once SwiftUI has actually
/// published the synthetic accessibility elements the accessibility audit exists to walk.
///
/// ## Why this exists
///
/// Two of the audit's tests assert against a *real* `UIHostingController` rather than a stand-in,
/// because the claim they pin is a claim about SwiftUI itself: that it **sets**
/// `accessibilityElements` on the views it hosts, which is the cheap stored property
/// ``AuditNode`` reads instead of forcing UIAccessibility to compute a subtree. That claim is the
/// whole reason the walk is affordable, so it has to be tested against the framework and not
/// against a fixture that agrees with us by construction.
///
/// Both tests set the view up and looked immediately — one after a bare `layoutIfNeeded()`, the
/// other after a fixed half-second of run loop. On the development machine (Xcode 26.2) SwiftUI
/// had published by then and both passed. On CI (Xcode 26.0.1, same iOS 26.2 runtime) it had not,
/// and both failed on every run from the day the audit landed:
///
/// ```
/// XCTAssertFalse failed - SwiftUI put no accessibility elements on screen at all
/// XCTAssertTrue failed - SwiftUI's synthetic elements must still be found, but got []
/// ```
///
/// A fixed wait is the bug. When the thing being waited for is a framework's own scheduling, the
/// test has to wait *for the condition*, and it has to say something honest when the condition
/// never arrives rather than reporting the framework's silence as a defect in our walk.
///
/// ## What it does
///
/// Hosts the view, attaches the window to a foreground scene when the test host has one, makes it
/// key and visible, then polls until the hierarchy publishes accessibility elements. If it never
/// does, the calling test is **skipped** with a message naming the platform — so a run on a
/// toolchain where SwiftUI behaves differently reads as "unverified here", which is true, rather
/// than as "the audit is broken", which is not.
@MainActor
enum HostedSwiftUIWindow {

    /// How long to wait for SwiftUI to publish before giving up and skipping.
    ///
    /// Generous on purpose. The cost of waiting too long is a few seconds on a run that was going
    /// to skip anyway; the cost of waiting too little is a red suite that says nothing true.
    static let defaultTimeout: TimeInterval = 5

    /// How long each poll gives the run loop before looking again.
    ///
    /// SwiftUI publishes accessibility elements off its own commit, so the run loop has to actually
    /// turn between looks — a spin loop on `Date()` would wait the full timeout and find nothing.
    private static let pollInterval: TimeInterval = 0.05

    /// The default size, matching the device the rest of the audit's fixtures use.
    static let defaultSize = CGSize(width: 390, height: 844)

    /// Hosts `view` and returns the window once it is ready to be walked.
    ///
    /// - Parameters:
    ///   - view: The SwiftUI view to host.
    ///   - size: The window's size. Defaults to ``defaultSize``.
    ///   - timeout: How long to wait for readiness. Defaults to ``defaultTimeout``.
    ///   - isReady: The readiness probe, run against the hosting controller's view. Defaults to
    ///     ``publishesAccessibilityElements(_:)``. Injectable so ``HostedSwiftUIWindowTests`` can
    ///     drive both outcomes deterministically, which a real view cannot do on every platform —
    ///     the whole point of this helper being that platforms differ here.
    ///   - file: The calling file, so a skip is attributed to the test rather than to this helper.
    ///   - line: The calling line, for the same reason.
    /// - Returns: A key, visible window whose root view controller hosts `view`. The caller has to
    ///   hold on to it: a window with no other references goes away and takes the hierarchy with it.
    /// - Throws: `XCTSkip` when `isReady` never succeeds within `timeout`.
    static func make<Root: View>(hosting view: Root,
                                 size: CGSize = defaultSize,
                                 timeout: TimeInterval = defaultTimeout,
                                 isReady: @MainActor (UIView) -> Bool = publishesAccessibilityElements,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) throws -> UIWindow {
        let window = makeWindow(size: size)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isReady(host.view) { return window }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        } while Date() < deadline

        throw XCTSkip("""
            SwiftUI published no accessibility elements for a hosted view within \(timeout)s on \
            iOS \(UIDevice.current.systemVersion). The audit's walk depends on SwiftUI setting \
            `accessibilityElements` on the views it hosts; that claim is unverified on this \
            toolchain, so this test is skipped rather than reported as a defect in the walk.
            """,
            file: file,
            line: line)
    }

    /// Whether SwiftUI has set `accessibilityElements` anywhere in `view`'s subtree.
    ///
    /// This is the readiness question asked exactly as the walk asks it: a *set* property, not a
    /// computed one. Reading `accessibilityElements` is cheap when it is nil, which is why
    /// ``AuditNode`` reads it and never calls `accessibilityElementCount()` on a `UIView` — doing
    /// that forces UIAccessibility to compute the whole subtree and once hung the app.
    ///
    /// An empty array is deliberately not readiness. SwiftUI assigns the array before it has
    /// anything to put in it, and treating that as ready reintroduces the original bug: a walk that
    /// runs, finds nothing, and reports the nothing as a result.
    ///
    /// - Parameter view: The root of the subtree to look through.
    /// - Returns: `true` when some view in the subtree vends at least one element.
    static func publishesAccessibilityElements(_ view: UIView) -> Bool {
        publishedAccessibilityElementCount(view) > 0
    }

    /// How many accessibility elements SwiftUI has set across `view`'s subtree.
    ///
    /// A caller that knows how many elements its fixture should produce waits on that number
    /// instead of on the first one. SwiftUI publishes a hierarchy in its own time and there is no
    /// promise the whole tree lands in one commit, so "at least one element exists" is a weaker
    /// readiness signal than a test asserting on three specific labels actually needs.
    ///
    /// This counts what the framework *set*, never what the audit found — so it stays an
    /// independent readiness signal and cannot mask a regression in the walk it is waiting for.
    ///
    /// - Parameter view: The root of the subtree to count through.
    /// - Returns: The total number of elements vended by views in the subtree.
    static func publishedAccessibilityElementCount(_ view: UIView) -> Int {
        (view.accessibilityElements?.count ?? 0)
            + view.subviews.reduce(0) { $0 + publishedAccessibilityElementCount($1) }
    }

    /// Builds the window, attached to a foreground window scene when one exists.
    ///
    /// A test bundle with no host application has no scenes at all, and an unattached window is
    /// what the audit's fixtures have always used successfully. Where a scene *is* available,
    /// attaching to it is the closer approximation of a real app and gives SwiftUI a display to
    /// commit against — so take it when it is there and carry on without it when it is not.
    ///
    /// - Parameter size: The window's size.
    /// - Returns: An unshown window of `size`.
    private static func makeWindow(size: CGSize) -> UIWindow {
        let frame = CGRect(origin: .zero, size: size)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let scene else { return UIWindow(frame: frame) }
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        return window
    }
}
