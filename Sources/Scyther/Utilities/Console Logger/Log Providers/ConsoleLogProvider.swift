//
//  File.swift
//
//
//  Created by Brandon Stillitano on 9/2/22.
//

import Foundation

// MARK: - Delegate
public protocol ConsoleLogProviderDelegate: AnyObject {
    func logProvider(_ provider: ConsoleLogProvider?, didRecieve log: ConsoleLog)
}

// MARK: - Public Protocol
public protocol ConsoleLogProvider: AnyObject {
    init?(queue: DispatchQueue, delegate: ConsoleLogProviderDelegate?)
    static var sourceName: String { get }
    func setup()
    func teardown()
}

// MARK: - Default Implementations
extension ConsoleLogProvider {
    static var sourceName: String {
        return String(describing: self)
    }
}
