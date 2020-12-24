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
}
