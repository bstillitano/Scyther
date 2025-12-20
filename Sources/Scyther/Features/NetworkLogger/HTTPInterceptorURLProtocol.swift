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
open class HTTPInterceptorURLProtocol: URLProtocol {
    private lazy var session: URLSession = { [unowned self] in
        return URLSession(configuration: .default,
                          delegate: self,
                          delegateQueue: nil)
    }()

    private let model: HTTPRequest = .init()
    private var response: URLResponse?
    private var responseData: NSMutableData?

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

        /// Continue executing request
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return
        }
        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: mutableRequest)
        session.dataTask(with: mutableRequest as URLRequest).resume()
    }

    override open func stopLoading() {
        session.getTasksWithCompletionHandler { dataTasks, _, _ in
            dataTasks.forEach { $0.cancel() }
        }
    }

    override open class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
}

extension HTTPInterceptorURLProtocol: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData?.append(data)

        client?.urlProtocol(self, didLoad: data)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        responseData = NSMutableData()

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

        Task {
            await NetworkLogger.instance.add(model)
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
