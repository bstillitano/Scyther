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
/// A marked request is therefore exempt from **every** interception feature — breakpoints, stubs,
/// header rewrites and conditioning, global or per-override — while still being logged. Seeing
/// what Scyther itself sends is useful; having it held hostage is not.
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
/// anything could set, but a UUID minted once per process and never published: an app cannot
/// guess it, cannot read it, and a stale value persisted from an earlier launch will not match.
/// The key alone is not enough to opt out — the value has to be this process's token.
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
    /// Unguessable and never sent anywhere, which is what makes the marker unspoofable by the
    /// host app's own traffic: knowing the key is not enough, and the value changes every launch.
    private static let token = UUID().uuidString

    /// Returns `request` marked as Scyther's own.
    ///
    /// - Parameter request: The request Scyther is about to send.
    /// - Returns: The same request, marked. Returned unchanged in the impossible case that it
    ///   cannot be copied — an unmarked request is merely interceptable, which is the behaviour
    ///   that shipped, so failing open is safer than failing to send at all.
    static func marked(_ request: URLRequest) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return request
        }
        mark(mutable)
        return mutable as URLRequest
    }

    /// Marks a mutable request as Scyther's own, in place.
    ///
    /// - Parameter request: The request to mark.
    static func mark(_ request: NSMutableURLRequest) {
        URLProtocol.setProperty(token, forKey: scytherOriginatedRequestKey, in: request)
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
}
