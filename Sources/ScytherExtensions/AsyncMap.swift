//
//  AsyncMap.swift
//  Scyther
//
//  Created by Brandon Stillitano on 28/6/2025.
//

import Foundation

@available(macOS 10.15, iOS 15.0, *)
extension Array {
    /// Asynchronously maps an array using the given async transform, preserving result order.
    /// - Parameter transform: An async function to apply to each element.
    /// - Returns: An array of results with the same order as the original array.
    public func asyncMap<T>(
        _ transform: @escaping (Element) async throws -> T
    ) async rethrows -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            // Enumerate to keep track of the original index
            for (index, element) in self.enumerated() {
                group.addTask {
                    let result = try await transform(element)
                    return (index, result)
                }
            }

            // Prepare a buffer with nils to be filled with results
            var results = Array<T?>(repeating: nil, count: self.count)

            for try await (index, result) in group {
                results[index] = result
            }

            // Force unwrap is safe here because we filled all slots
            return results.map { $0! }
        }
    }
}
