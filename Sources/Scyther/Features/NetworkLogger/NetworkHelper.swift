//
//  NetworkHelper.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

/// Manages network request interception and logging for the Scyther debugging framework.
///
/// `NetworkHelper` provides the core functionality for intercepting HTTP/HTTPS requests
/// made by the application. It registers a custom `URLProtocol` to capture all network
/// traffic and maintains configuration for filtering and caching.
///
/// ## Features
/// - Automatic request and response logging
/// - URL filtering to exclude specific endpoints
/// - Support for custom URL session configurations
/// - IP address resolution
/// - Content type filtering
///
/// ## Usage
/// ```swift
/// // Start network logging (typically called once during app startup)
/// NetworkHelper.instance.start()
///
/// // Ignore specific URLs
/// NetworkHelper.instance.ignoredURLs = ["https://analytics.example.com"]
///
/// // Access the device's IP address
/// let ip = await NetworkHelper.instance.ipAddress
/// ```
///
/// - Note: Network logging uses method swizzling to intercept `URLSession` requests.
public class NetworkHelper {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() {}

    /// An initialised, shared instance of the `NetworkHelper` class.
    static let instance = NetworkHelper()

    /// URLs that will not be logged or intercepted by Scyther.
    ///
    /// Add URL prefixes to this array to exclude them from network logging.
    /// Useful for preventing infinite loops or excluding analytics/telemetry endpoints.
    ///
    /// ## Example
    /// ```swift
    /// NetworkHelper.instance.ignoredURLs = [
    ///     "https://analytics.example.com",
    ///     "https://telemetry.example.com"
    /// ]
    /// ```
    public var ignoredURLs: [String] = []

    /// The cache storage policy for network requests.
    ///
    /// Determines how the network helper should cache requests and responses.
    /// Defaults to `.notAllowed` to prevent caching of intercepted requests.
    var cacheStoragePolicy = URLCache.StoragePolicy.notAllowed

    /// Content type filters for displaying network logs.
    ///
    /// A boolean array representing which content types should be shown in the UI.
    /// Indices correspond to `HTTPModelShortType.allCases`.
    private var filters: [Bool] = []

    /// Returns the cached content type filters.
    ///
    /// If not yet initialized, creates a default array with all content types enabled.
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

    /// The current IP address of the device.
    ///
    /// This property asynchronously fetches the device's public IP address using the ipify API.
    /// The result is cached after the first successful fetch.
    ///
    /// ## Example
    /// ```swift
    /// let ip = await NetworkHelper.instance.ipAddress
    /// print("Device IP: \(ip)")
    /// ```
    ///
    /// - Returns: The IP address as a string, or "0.0.0.0" if unavailable.
    public var ipAddress: String {
        get async {
            guard !hasResolvedIPAddress else { return _ipAddress }
            _ipAddress = await getIPAddress()
            hasResolvedIPAddress = true
            return _ipAddress
        }
    }

    /// Internal storage for the cached IP address.
    private var _ipAddress: String = ""

    /// Flag indicating whether the IP address has been resolved.
    private var hasResolvedIPAddress: Bool = false
}

// MARK: - Lifecycle
extension NetworkHelper {
    /// Starts network logging by registering the HTTP interceptor protocol.
    ///
    /// This method performs the following:
    /// 1. Swizzles `URLSessionConfiguration` to intercept default sessions
    /// 2. Registers `HTTPInterceptorURLProtocol` to capture network traffic
    ///
    /// Call this method once during application startup to enable network logging.
    func start() {
        // Register `URLProtocol` class for network logging to intercept requests. Swizzling required because libraries like Alamofire don't use the shared NSURLSession instance but instead use their own instance.
        URLSessionConfiguration.swizzleDefaultSessionConfiguration()
        enable(true)
    }
}

// MARK: - Enablers
extension NetworkHelper {
    /// Enables or disables network logging globally.
    ///
    /// - Parameter enable: `true` to enable logging, `false` to disable.
    func enable(_ enable: Bool) {
        if enable {
            URLProtocol.registerClass(HTTPInterceptorURLProtocol.self)
        } else {
            URLProtocol.unregisterClass(HTTPInterceptorURLProtocol.self)
        }
    }

    /// Enables or disables network logging for a specific session configuration.
    ///
    /// This method adds or removes the `HTTPInterceptorURLProtocol` from the
    /// configuration's protocol classes array.
    ///
    /// - Parameters:
    ///   - enabled: `true` to enable logging, `false` to disable.
    ///   - sessionConfiguration: The `URLSessionConfiguration` to modify.
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
    /// Retrieves the current IP Address of the device asynchronously.
    ///
    /// Makes a request to the ipify API to determine the device's public IP address.
    ///
    /// - Returns: The IP address as a string, or "0.0.0.0" if the request fails.
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
