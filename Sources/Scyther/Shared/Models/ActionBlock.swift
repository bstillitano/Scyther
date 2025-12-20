//
//  ActionBlock.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import Foundation

/// A closure type that represents a simple action or event with no parameters and no return value.
///
/// `ActionBlock` is commonly used throughout Scyther to define callbacks for user interactions,
/// view events, and completion handlers where no data needs to be passed.
///
/// ## Usage Example
///
/// ```swift
/// let button = UIButton()
/// var onTap: ActionBlock = {
///     print("Button tapped!")
/// }
/// button.addAction(UIAction { _ in onTap() }, for: .touchUpInside)
/// ```
///
/// ## Common Use Cases
/// - Button tap handlers
/// - Completion callbacks
/// - View event handlers
/// - Simple closure-based actions
///
/// - Note: For actions that need to pass data, use ``ActionBlockWithData`` instead.
public typealias ActionBlock = () -> Void

/// A closure type that represents an action or event with a single generic parameter and no return value.
///
/// `ActionBlockWithData` extends the concept of ``ActionBlock`` by allowing a single parameter
/// of any type to be passed to the closure. This is useful for callbacks that need to receive
/// data from the event source.
///
/// ## Usage Example
///
/// ```swift
/// struct UserProfile {
///     let name: String
///     let email: String
/// }
///
/// var onProfileSelected: ActionBlockWithData<UserProfile> = { profile in
///     print("Selected user: \(profile.name)")
/// }
///
/// let profile = UserProfile(name: "John Doe", email: "john@example.com")
/// onProfileSelected(profile)
/// ```
///
/// ## Common Use Cases
/// - Table view cell selection handlers with the selected item
/// - Form field value change callbacks
/// - Network response handlers with response data
/// - State change notifications with the new state
///
/// - Parameter T: The type of data passed to the closure
///
/// - Note: For actions that don't need to pass data, use ``ActionBlock`` instead.
public typealias ActionBlockWithData<T> = (T) -> Void
