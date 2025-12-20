//
//  EdgeInsets+Extensions.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/6/2025.
//

import SwiftUI

/// Provides convenient extensions for EdgeInsets in SwiftUI.
///
/// This extension adds common preset values for EdgeInsets to simplify layout code.
extension EdgeInsets {
    /// A zero-valued EdgeInsets with all edges set to zero.
    ///
    /// This is equivalent to creating `EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)`.
    ///
    /// ## Example
    /// ```swift
    /// Text("Hello, World!")
    ///     .padding(.zero) // Applies no padding
    ///
    /// VStack {
    ///     // Content
    /// }
    /// .padding(EdgeInsets.zero) // Explicitly no padding
    /// ```
    static let zero: EdgeInsets = EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: .zero)
}
