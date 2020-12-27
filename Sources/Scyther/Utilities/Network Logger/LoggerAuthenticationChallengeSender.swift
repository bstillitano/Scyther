//
//  LoggerAuthenticationChallengeSender.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

class LoggerAuthenticationChallengeSender: NSObject, URLAuthenticationChallengeSender {

    typealias LoggerAuthenticationChallengeHandler = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    let handler: LoggerAuthenticationChallengeHandler

    init(handler: @escaping LoggerAuthenticationChallengeHandler) {
        self.handler = handler
        super.init()
    }

    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        handler(.useCredential, credential)
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        handler(.useCredential, nil)
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        handler(.cancelAuthenticationChallenge, nil)
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        handler(.performDefaultHandling, nil)
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        handler(.rejectProtectionSpace, nil)
    }
}
