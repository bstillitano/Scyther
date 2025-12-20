//
//  NetworkLogger.swift
//  
//
//  Created by Brandon Stillitano on 24/12/20.
//

import Foundation

actor NetworkLogger {
    static let instance = NetworkLogger()
    var items = [HTTPRequest]()
    
    private var continuation: AsyncStream<[HTTPRequest]>.Continuation?
    var updates: AsyncStream<[HTTPRequest]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(self.items) // push initial value
        }
    }
    
    private init() { }

    func add(_ obj: HTTPRequest) {
        items.insert(obj, at: 0)
        continuation?.yield(items)
    }
    
    func clear() {
        items.removeAll()
        continuation?.yield(items)
    }
}
