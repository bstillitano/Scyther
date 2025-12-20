//
//  NetworkHelper.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

/// Utility class used to monitor and subsequently log networking requests made by registering a `URLProtocol`
public class NetworkHelper {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() {}

    /// An initialised, shared instance of the `NetworkHelper` class.
    static let instance = NetworkHelper()

    /// URLs that will not be logged or intercepted by Scyther.
    public var ignoredURLs: [String] = []

    /// `URLCache.StoragePolicy` representing how `NetworkHelper` should cache requests and subsequently pass them on.
    var cacheStoragePolicy = URLCache.StoragePolicy.notAllowed

    /// `Bool` array representing whether filters should be cached.
    private var filters: [Bool] = []
    public var cachedFilters: [Bool] {
        get {
            if filters.isEmpty {
                filters = [Bool](repeating: true, count: HTTPModelShortType.allCases.count)
            }
            return filters
        }
        set {
            filters = newValue
        }
    }

    /// The current IP address of the device running the `NetworkHelper` utility clas
    public var ipAddress: String {
        get async {
            guard !hasResolvedIPAddress else { return _ipAddress }
            _ipAddress = await getIPAddress()
            hasResolvedIPAddress = true
            return _ipAddress
        }
    }
    private var _ipAddress: String = ""
    private var hasResolvedIPAddress: Bool = false
}

// MARK: - Lifecycle
extension NetworkHelper {
    func start() {
        // Register `URLProtocol` class for network logging to intercept requests. Swizzling required because libraries like Alamofire don't use the shared NSURLSession instance but instead use their own instance.
        URLSessionConfiguration.swizzleDefaultSessionConfiguration()
        enable(true)
    }
}

// MARK: - Enablers
extension NetworkHelper {
    func enable(_ enable: Bool) {
        if enable {
            URLProtocol.registerClass(HTTPInterceptorURLProtocol.self)
        } else {
            URLProtocol.unregisterClass(HTTPInterceptorURLProtocol.self)
        }
    }

    func enable(_ enabled: Bool, sessionConfiguration: URLSessionConfiguration) {
        guard var urlProtocolClasses = sessionConfiguration.protocolClasses else { return }

        let index = urlProtocolClasses.firstIndex(where: { $0 == HTTPInterceptorURLProtocol.self })
        if enabled == true, index == nil {
            urlProtocolClasses.insert(HTTPInterceptorURLProtocol.self, at: 0)
        } else if let index, enabled == false {
            urlProtocolClasses.remove(at: index)
        }
        sessionConfiguration.protocolClasses = urlProtocolClasses

        enable(enabled)
    }
}

// MARK: - IP Address
extension NetworkHelper {
    /// Retrieves the current IP Address of the device asynchronously
    private func getIPAddress() async -> String {
        // Construct API URL
        guard let url = URL(string: "https://api.ipify.org/?format=json") else {
            return "0.0.0.0"
        }

        // Setup network request
        let urlRequest = URLRequest(url: url)

        // Attempt network request
        do {
            // Perform network request
            let (data, _) = try await URLSession.shared.data(for: urlRequest)

            // Parse JSON response
            if let json = try JSONSerialization.jsonObject(with: data, options: [.allowFragments]) as? [String: Any],
               let ipAddress = json["ip"] as? String
            {
                return ipAddress
            } else {
                return "0.0.0.0"
            }
        } catch {
            return "0.0.0.0"
        }
    }
}
