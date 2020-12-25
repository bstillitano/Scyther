//
//  Logger.swift
//
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

public class Logger {
    /// Private Init to Stop re-initialisation and allow singleton creation.
    private init() { }

    /// An initialised, shared instance of the `Logger` class.
    static let instance = Logger()

    /// URLs that will not be logged or intercepted by Scyther.
    public var ignoredURLs: [String] = []

    /// `URLCache.StoragePolicy` representing how `Logger` should cache requests and subsequently pass them on.
    internal var cacheStoragePolicy = URLCache.StoragePolicy.notAllowed

    /// `Bool` array representing whether filters should be cached.
    private var filters: [Bool] = []
    public var cachedFilters: [Bool] {
        get {
            if self.filters.isEmpty {
                self.filters = [Bool](repeating: true, count: HTTPModelShortType.allCases.count)
            }
            return self.filters
        }
        set {
            self.filters = newValue
        }
    }

    /// The current IP address of the device running the `Logger` utility clas
    public var ipAddress: String = "0.0.0.0"
}

extension Logger {
    /// Retrieves the current IP Address of the device asynchronously
    class func getIPAddress(_ completion: @escaping (_ result: String) -> Void) {
        /// Construct API URL
        guard let url: URL = URL(string: "https://api.ipify.org/?format=json") else {
            completion("0.0.0.0")
            return
        }

        /// Setup network request
        let urlRequest: NSMutableURLRequest = NSMutableURLRequest(url: url)
        URLProtocol.setProperty("1", forKey: "LoggerInternal", in: urlRequest)

        /// Perform network request
        URLSession.shared.dataTask(with: urlRequest as URLRequest) { data, response, error in
            /// Check that data is available
            guard let data: Data = data else {
                completion("0.0.0.0")
                return
            }
            
            /// Serialize JSON response into `AnyObject`
            guard let jsonData = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) else {
                completion("0.0.0.0")
                return
            }
            
            /// Check response data for `ip` key
            guard let ipAddress: String = (jsonData as AnyObject).value(forKey: "ip") as? String else {
                completion("0.0.0.0")
                return
            }
            completion(ipAddress)
        }.resume()
    }
}
