//
//  HTTPInterceptorURLProtocol.swift
//
//
//  Created by Brandon Stillitano on 22/12/20.
//

import Foundation

/// Property key used to mark requests as internal to prevent infinite logging loops.
internal let internalNetworkRequestKey = "Scyther_Internal_Network_Request"

/// A custom `URLProtocol` subclass that intercepts HTTP/HTTPS requests for logging.
///
/// `HTTPInterceptorURLProtocol` acts as a man-in-the-middle for network requests,
/// capturing request and response data without interfering with normal operation.
/// It stores captured data in `HTTPRequest` objects and adds them to `NetworkLogger`.
///
/// ## How It Works
/// 1. When registered with `URLProtocol.registerClass()`, this class can inspect all URL loading requests
/// 2. It creates a new URLSession to execute the actual request
/// 3. As data arrives, it's forwarded to the original client while being captured for logging
/// 4. Complete request/response data is stored in `HTTPRequest` and logged to `NetworkLogger`
///
/// ## Features
/// - Transparent request/response capture
/// - Authentication challenge handling
/// - HTTP redirect support
/// - Request filtering based on URL patterns
/// - Automatic prevention of infinite logging loops
///
/// - Note: This protocol is automatically registered by `NetworkHelper.start()`.
open class HTTPInterceptorURLProtocol: URLProtocol, @unchecked Sendable {
    private lazy var session: URLSession = { [unowned self] in
        return URLSession(configuration: .default,
                          delegate: self,
                          delegateQueue: nil)
    }()

    private let model: HTTPRequest = .init()
    private var response: URLResponse?
    private var responseData: NSMutableData?

    /// The conditioning a matching rule asked for, stored at `startLoading()` so that
    /// `urlSession(_:dataTask:didReceive:)` can throttle the bytes it forwards.
    ///
    /// - Note: Internal rather than private so a test can drive the delegate callbacks directly
    ///   and measure the pacing. Nothing but `startLoading()` writes it in production.
    internal var condition: NetworkCondition?

    /// Whether a real data task was started. A stubbed or rule-failed request never creates one,
    /// so `stopLoading()` must not spin up the lazy session just to cancel nothing.
    private var didStartTask: Bool = false

    /// Set by `stopLoading()` so a bandwidth throttle mid-sleep stops forwarding bytes to a client
    /// that has gone away instead of running its budget out.
    private var isCancelled: Bool = false

    /// Paces the current response to the ceiling ``condition`` asked for, or `nil` when there is
    /// no ceiling. Rebuilt when a response begins, because the budget is per response.
    private var throttle: BandwidthThrottle?

    /// When the current response began arriving, which is what the throttle measures against.
    private var responseStart: Date = .distantPast

    /// The longest a rule is allowed to block the URL loading system's thread in one go.
    ///
    /// A developer typing an unreasonable latency into the menu should see a slow request, not a
    /// request that appears to have hung forever.
    private static let maximumSleep: TimeInterval = 30

    /// The longest the bandwidth throttle may spend asleep across one whole response.
    private static let maximumBandwidthSleep: TimeInterval = 30

    override open class func canInit(with request: URLRequest) -> Bool {
        return canServeRequest(request)
    }

    override open class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canServeRequest(request)
    }

    private class func canServeRequest(_ request: URLRequest) -> Bool {
        /// Check that Scyther has been started and should intercept requests
        guard Scyther.isStarted else {
            return false
        }

        /// Verify that the URL being requested is not a URL that is from our internal  `ScytherProtocol`
        guard URLProtocol.property(forKey: internalNetworkRequestKey, in: request) == nil else {
            return false
        }

        /// Verify that the URL is an `http` and/or `https` URL
        guard let url = request.url, url.absoluteString.hasPrefix("http") || url.absoluteString.hasPrefix("https") else {
            return false
        }

        /// Confirm that the URL is not a URL that should be ignored by the `NetworkHelper` utility class.
        let absoluteString = url.absoluteString
        guard !NetworkHelper.instance.ignoredURLs.contains(where: { absoluteString.hasPrefix($0) }) else {
            return false
        }

        return true
    }

    override open func startLoading() {
        /// Save request to local model
        model.saveRequest(request)

        /// Resolve any rules that apply to this request. The snapshot is lock-guarded because
        /// this method runs on a thread owned by the URL loading system.
        let snapshot = NetworkRuleSnapshot.current
        let outcome = snapshot.isEnabled
            ? NetworkRuleEngine.outcome(for: request, rules: snapshot.rules)
            : .empty
        model.appliedRuleNames = outcome.appliedRuleNames
        condition = outcome.condition

        if let stub = outcome.stub, let url = request.url {
            let bodies = { NetworkRuleStore.bodyDataOffMainActor(for: $0) }
            if let (response, body) = NetworkRuleStubResponder.response(for: stub, url: url, bodyProvider: bodies) {
                serve(response, body: body, after: NetworkRuleStubResponder.delay(for: stub))
                return
            }
        }

        /// Continue executing request
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return
        }

        /// Apply any header rewrite, then re-capture the request so the log describes what actually
        /// goes on the wire. Without the second `saveRequest` a developer checking whether their
        /// rewrite rule worked would see the pre-rewrite headers and cURL and conclude it had not.
        if let rewrite = outcome.headerRewrite {
            rewrite.apply(to: mutableRequest)
            model.saveRequest(mutableRequest as URLRequest)
        }

        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: mutableRequest)

        if let condition = outcome.condition {
            if condition.failureRate > 0, Double.random(in: 0...1) < condition.failureRate {
                let error = URLError(URLError.Code(rawValue: condition.failureCode))
                model.saveErrorResponse()
                finishWithFailure(error)
                return
            }
            if condition.latency > 0 {
                Thread.sleep(forTimeInterval: min(condition.latency, Self.maximumSleep))
            }
        }

        didStartTask = true
        session.dataTask(with: mutableRequest as URLRequest).resume()
    }

    /// Hands a rule's synthesised response to the client as though it had come from the network.
    ///
    /// No data task is created, so a mocked request never leaves the device. The response is
    /// logged exactly as a real one is, with ``HTTPRequest/wasStubbed`` set so the log can say
    /// where it came from.
    ///
    /// - Parameters:
    ///   - response: The response to serve.
    ///   - body: The response body.
    ///   - delay: Seconds to wait before serving, capped at ``maximumSleep``. Slept on the URL
    ///     loading system's thread, never the main one.
    private func serve(_ response: HTTPURLResponse, body: Data, after delay: TimeInterval) {
        if delay > 0 {
            Thread.sleep(forTimeInterval: min(delay, Self.maximumSleep))
        }

        client?.urlProtocol(self,
                            didReceive: response,
                            cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)

        model.saveRequestBody(request)
        model.logRequest(request)
        model.wasStubbed = true
        model.saveResponse(response, data: body)

        let capturedModel = model
        Task { @MainActor in
            await NetworkLogger.instance.add(capturedModel)
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
        }
    }

    /// Fails the request with the error a condition rule asked for, and logs the attempt.
    ///
    /// - Parameter error: The error to surface to the caller.
    private func finishWithFailure(_ error: URLError) {
        client?.urlProtocol(self, didFailWithError: error)

        model.saveRequestBody(request)
        model.logRequest(request)

        let capturedModel = model
        Task { @MainActor in
            await NetworkLogger.instance.add(capturedModel)
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
        }
    }

    override open func stopLoading() {
        isCancelled = true
        guard didStartTask else { return }
        session.getTasksWithCompletionHandler { dataTasks, _, _ in
            dataTasks.forEach { $0.cancel() }
        }
    }

    override open class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
}

extension HTTPInterceptorURLProtocol: URLSessionDataDelegate {
    /// Forwards received bytes to the client, honouring any bandwidth ceiling a condition rule set.
    ///
    /// The ceiling is a budget for the **whole response**, held by ``BandwidthThrottle`` and reset
    /// when a response begins. Weighing only the bytes in hand would never sleep for a realistic
    /// ceiling, because `URLSession` delivers a body in chunks far smaller than a second's worth
    /// of it. The wait happens on the private session's own serial delegate queue, which belongs
    /// to this request alone, and never on the main thread. Two bounds keep it from becoming a
    /// hang:
    ///
    /// - The throttle asks for at most `maximumBandwidthSleep` seconds across the whole response,
    ///   after which the remaining bytes are forwarded as fast as they arrive.
    /// - Nothing is forwarded once `stopLoading()` has been called, so a cancelled request does
    ///   not keep pushing bytes at a client that has gone away.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData?.append(data)

        guard let wait = throttle?.delay(forwarding: data.count,
                                         elapsed: Date().timeIntervalSince(responseStart)) else {
            client?.urlProtocol(self, didLoad: data)
            return
        }

        if wait > 0 {
            if isCancelled { return }
            Thread.sleep(forTimeInterval: wait)
        }
        if isCancelled { return }
        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        responseData = NSMutableData()
        responseStart = Date()
        throttle = BandwidthThrottle(bandwidthKBps: condition?.bandwidthKBps,
                                     maximumTotalSleep: Self.maximumBandwidthSleep)

        client?.urlProtocol(self,
                            didReceive: response,
                            cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            if let error = error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        guard let request = task.originalRequest else {
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
            return
        }

        model.saveRequestBody(request)
        model.logRequest(request)

        if error != nil {
            model.saveErrorResponse()
        } else if let response = response {
            let data = (responseData ?? NSMutableData()) as Data
            model.saveResponse(response, data: data)
        }

        let capturedModel = model
        Task { @MainActor in
            await NetworkLogger.instance.add(capturedModel)
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let updatedRequest: URLRequest
        if URLProtocol.property(forKey: internalNetworkRequestKey, in: request) != nil {
            let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.removeProperty(forKey: internalNetworkRequestKey, in: mutableRequest)

            updatedRequest = mutableRequest as URLRequest
        } else {
            updatedRequest = request
        }

        client?.urlProtocol(self, wasRedirectedTo: updatedRequest, redirectResponse: response)
        completionHandler(updatedRequest)
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let wrappedChallenge = URLAuthenticationChallenge(authenticationChallenge: challenge, sender: LoggerAuthenticationChallengeSender(handler: completionHandler))
        client?.urlProtocol(self, didReceive: wrappedChallenge)
    }

    #if !os(OSX)
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        client?.urlProtocolDidFinishLoading(self)
    }
    #endif
}
