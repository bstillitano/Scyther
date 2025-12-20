//
//  LoggerAuthenticationChallengeSender.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

/// A custom authentication challenge sender used by the network logger.
///
/// This class wraps authentication challenge responses and forwards them to a completion handler.
/// It's used internally by `HTTPInterceptorURLProtocol` to properly handle authentication challenges
/// while maintaining the ability to log network requests.
///
/// - Note: This is an internal implementation detail of the network logging system.
class LoggerAuthenticationChallengeSender: NSObject, URLAuthenticationChallengeSender {

    /// Type alias for the authentication challenge completion handler.
    ///
    /// - Parameters:
    ///   - disposition: How the challenge should be handled.
    ///   - credential: The credential to use, if any.
    typealias LoggerAuthenticationChallengeHandler = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    /// The completion handler to call when an authentication decision is made.
    let handler: LoggerAuthenticationChallengeHandler

    /// Creates a new authentication challenge sender.
    ///
    /// - Parameter handler: The completion handler to invoke when authentication decisions are made.
    init(handler: @escaping LoggerAuthenticationChallengeHandler) {
        self.handler = handler
        super.init()
    }

    /// Attempts to use the provided credential for authentication.
    ///
    /// - Parameters:
    ///   - credential: The credential to use.
    ///   - challenge: The authentication challenge being responded to.
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        handler(.useCredential, credential)
    }

    /// Continues without providing a credential.
    ///
    /// - Parameter challenge: The authentication challenge being responded to.
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        handler(.useCredential, nil)
    }

    /// Cancels the authentication challenge.
    ///
    /// - Parameter challenge: The authentication challenge to cancel.
    func cancel(_ challenge: URLAuthenticationChallenge) {
        handler(.cancelAuthenticationChallenge, nil)
    }

    /// Performs the default handling for the authentication challenge.
    ///
    /// - Parameter challenge: The authentication challenge to handle.
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        handler(.performDefaultHandling, nil)
    }

    /// Rejects the protection space and continues with the authentication process.
    ///
    /// - Parameter challenge: The authentication challenge being responded to.
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        handler(.rejectProtectionSpace, nil)
    }
}
