//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import Foundation

/// Empty protocol class used to provide default values. Do not use this class for anything other than static presets.
public class ProtocolDefaultsLogProvider: ConsoleLogProvider {
    required public init?(queue: DispatchQueue, delegate: ConsoleLogProviderDelegate?) {
        assertionFailure("This class is intentionally unimplemented. Please do not use.")
    }

    public func setup() {
        assertionFailure("This class is intentionally unimplemented. Please do not use.")
    }

    public func teardown() {
        assertionFailure("This class is intentionally unimplemented. Please do not use.")
    }

    public static var sourceName: String {
        return ""
    }
}


// MARK: - Presets
public extension ProtocolDefaultsLogProvider {
    static var allProviders: [ConsoleLogProvider.Type] {
        return [StandardStreamLogProvider.self, OSLogProvider.self]
    }

    static var standardStreamLogProvider: ConsoleLogProvider.Type {
        return StandardStreamLogProvider.self
    }

    static var osLogProvider: ConsoleLogProvider.Type {
        return OSLogProvider.self
    }
}
