//
//  ScytherOriginatedRequest.swift
//  Scyther
//
//  Created by Brandon Stillitano on 7/9/2026.
//

import Foundation

/// Property key marking a request Scyther itself put on the wire.
///
/// Distinct from ``internalNetworkRequestKey``, which means "the interceptor has already claimed
/// this one, do not claim it again". This one means "the app did not ask for this request,
/// Scyther did" — the request is still captured and still appears in the log, but nothing the
/// developer configured is allowed to interfere with it.
internal let scytherOriginatedRequestKey = "Scyther_Originated_Request"

/// Property key marking a Scyther request that has opted **back into** Request Overrides.
///
/// Only the replay editor sets it, and only when the developer switches its **Apply Request
/// Overrides** toggle on. It relaxes two thirds of the exemption — stubs and conditioning apply
/// again — and none of the other third: breakpoints and header rewrites are never applied to a
/// request Scyther sent, whatever this says.
internal let scytherAppliesOverridesKey = "Scyther_Applies_Overrides"

/// Marks, and recognises, the requests Scyther sends on its own behalf.
///
/// ## Why this exists
///
/// Scyther's own traffic used to travel through ``HTTPInterceptorURLProtocol`` indistinguishably
/// from the host app's, which meant the toolkit instrumented itself. A breakpoint on
/// `api.ipify.org` held the menu's own IP lookup, and the held-request editor was presented over
/// the menu — which re-created the menu, which fired the lookup again, which was held again. One
/// modal per second, stacking without limit, and the one screen a developer would use to switch
/// the breakpoint off was buried underneath them. An override could stub the same lookup, and
/// global conditioning could slow or fail it, for the same reason.
///
/// A marked request is therefore exempt from the interception features while still being logged.
/// Seeing what Scyther itself sends is useful; having it held hostage is not.
///
/// ## What the exemption covers
///
/// Two of the four are unconditional, because they are self-inflicted rather than preferences:
///
/// - **Breakpoints.** A held request that Scyther is itself waiting on deadlocks against the
///   screen that sent it — the ipify bug, and the same shape one layer up when a replay is held
///   by the editor that sent it.
/// - **Header rewrites.** The replay editor's whole promise is *this request, exactly as edited*;
///   a rewrite silently restoring a header the developer had just deleted contradicts the screen.
///
/// The other two — **stubs** and **conditioning** — are exempt by default and can be opted back
/// into per request, which the replay editor exposes as a toggle. "Replay this captured request
/// into the mock I have just written" is a real workflow and the only way to fire a specific,
/// crafted request at an override without waiting for the app to make the call itself; the same
/// goes for replaying one on a lossy link. Nothing opts the IP lookup back in, and nothing can:
/// the opt-in travels on the request, and only Scyther can put it there.
///
/// ## Why a `URLProtocol` property and not a header
///
/// A header would have been simpler and is wrong on three counts. It travels to the developer's
/// server, which is a request Scyther has no business editing; it is trivially spoofable, because
/// any app that set the same header would silently opt its own traffic out of the developer's own
/// breakpoints; and stripping it again before the request goes out means the marker has to survive
/// a round trip through the very code that removes it.
///
/// A `URLProtocol` property has none of those problems. It is process-local metadata attached to
/// an `NSURLRequest`, so it never reaches the wire, and it is copied along with the request by
/// `mutableCopy()` — which is how it survives the rewrite copy, the breakpoint rebuild and the
/// redirect copy the interceptor makes.
///
/// Spoofing is closed off by ``token``. The value stored under the key is not a `Bool` that
/// anything could set, but a UUID minted once per process: it cannot be guessed, and a stale value
/// persisted from an earlier launch does not match. The key alone is not enough to opt out — the
/// value has to be this launch's token.
///
/// It is not a secret, and the DocC used to claim it was. A host app that registers a `URLProtocol`
/// of its own is consulted about Scyther's outgoing requests like any other, and
/// `URLProtocol.property(forKey:in:)` is public API, so anything already running in this process
/// can read the token and then forge it. That is not a threat worth designing against — the
/// adversary would be the developer's own app evading the developer's own breakpoints — but the
/// guarantee is "unguessable and per-launch", not "unreadable".
///
/// ## Topics
///
/// ### Marking
/// - ``marked(_:)``
/// - ``mark(_:)``
///
/// ### Recognising
/// - ``identifies(_:)``
enum ScytherOriginatedRequest {
    /// The value a marked request carries, minted once per process.
    ///
    /// Unguessable and never sent anywhere, which is what stops the host app's ordinary traffic
    /// opting itself out: knowing the key is not enough, and the value changes every launch. It is
    /// not a secret from code already running in this process — see the type's discussion.
    private static let token = UUID().uuidString

    /// Returns `request` marked as Scyther's own.
    ///
    /// - Parameters:
    ///   - request: The request Scyther is about to send.
    ///   - applyingOverrides: Whether stubs and conditioning should apply to it anyway. Breakpoints
    ///     and header rewrites never do.
    /// - Returns: The same request, marked. Returned unchanged in the impossible case that it
    ///   cannot be copied — an unmarked request is merely interceptable, which is the behaviour
    ///   that shipped, so failing open is safer than failing to send at all.
    static func marked(_ request: URLRequest, applyingOverrides: Bool = false) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return request
        }
        mark(mutable, applyingOverrides: applyingOverrides)
        return mutable as URLRequest
    }

    /// Marks a mutable request as Scyther's own, in place.
    ///
    /// The opt-in is written or cleared rather than only written, so that re-stamping a copy —
    /// which is what the interceptor does on the network path and on a redirect — can never
    /// promote a request that had not asked for overrides.
    ///
    /// - Parameters:
    ///   - request: The request to mark.
    ///   - applyingOverrides: Whether stubs and conditioning should apply to it anyway.
    static func mark(_ request: NSMutableURLRequest, applyingOverrides: Bool = false) {
        URLProtocol.setProperty(token, forKey: scytherOriginatedRequestKey, in: request)
        if applyingOverrides {
            URLProtocol.setProperty(token, forKey: scytherAppliesOverridesKey, in: request)
        } else {
            URLProtocol.removeProperty(forKey: scytherAppliesOverridesKey, in: request)
        }
    }

    /// Whether this request is one Scyther sent on its own behalf.
    ///
    /// Compares the stored value against ``token`` rather than merely testing for the key's
    /// presence, so a request that carries the key with anything else in it — an app that guessed
    /// the key, a value copied out of an earlier launch — is treated as ordinary app traffic.
    ///
    /// - Parameter request: The request to test.
    /// - Returns: Whether the interception features must leave it alone.
    static func identifies(_ request: URLRequest) -> Bool {
        URLProtocol.property(forKey: scytherOriginatedRequestKey, in: request) as? String == token
    }

    /// Whether this Scyther request asked for stubs and conditioning to apply to it after all.
    ///
    /// Never consulted for a request that is not Scyther's own, and never relaxes the breakpoint
    /// or header-rewrite half of the exemption. Compared against ``token`` for the same reason
    /// ``identifies(_:)`` is: an app that guessed the key must not be able to opt anything into
    /// anything.
    ///
    /// - Parameter request: The request to test.
    /// - Returns: Whether Request Overrides may stub or condition it.
    static func appliesOverrides(_ request: URLRequest) -> Bool {
        URLProtocol.property(forKey: scytherAppliesOverridesKey, in: request) as? String == token
    }
}
