//
//  UIActivity+Extensions.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import UIKit

/// A custom UIActivity for saving files to the desktop when running on macOS Simulator.
///
/// This internal activity type extends UIActivityViewController to provide a convenient way
/// to save shared items directly to the desktop when debugging on the macOS Simulator.
/// This is particularly useful for inspecting exported files, logs, or debug data.
///
/// ## Usage
/// This activity is typically added to a UIActivityViewController automatically by Scyther
/// when running in the simulator environment.
///
/// ## Example
/// ```swift
/// let activity = SaveToDesktopActivity(title: "Save to Desktop") { items in
///     // Handle saving items to desktop
///     for item in items {
///         if let data = item as? Data {
///             // Save data to desktop
///         }
///     }
/// }
/// ```
internal class SaveToDesktopActivity: UIActivity {
    // MARK: - Data

    /// The items to be saved when the activity is performed.
    var activityItems: [Any] = []

    /// The title displayed for this activity in the activity view controller.
    private var title: String?

    /// The closure to execute when the activity is performed.
    private var actionBlock: ActionBlockWithData<[Any]>?

    // MARK: - Lifecycle

    /// Cleans up resources when the activity is deallocated.
    deinit {
        title = nil
        actionBlock = nil
    }

    /// Initializes a new save to desktop activity.
    ///
    /// - Parameters:
    ///   - title: The title to display for this activity
    ///   - actionBlock: The closure to execute when the activity is performed,
    ///                  receiving the activity items as a parameter
    init(title: String, actionBlock: ActionBlockWithData<[Any]>?) {
        self.title = title
        self.actionBlock = actionBlock
        super.init()
    }

    // MARK: - Overrides

    /// The title displayed for this activity in the share sheet.
    override var activityTitle: String? {
        return title
    }

    /// The image displayed for this activity in the share sheet.
    ///
    /// Uses the SF Symbol "desktopcomputer.and.arrow.down" to represent saving to desktop.
    override var activityImage: UIImage? {
        return UIImage(systemName: "desktopcomputer.and.arrow.down")
    }

    /// A unique identifier for this activity type.
    ///
    /// - Returns: A unique activity type identifier for Scyther's save to desktop activity.
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType(rawValue: "io.stillitano.ScytherInternal.saveToDesktopActivity")
    }

    /// The category of this activity.
    ///
    /// - Returns: `.action` to indicate this is an action-type activity.
    override class var activityCategory: UIActivity.Category {
        return .action
    }

    /// Determines whether this activity can be performed with the given items.
    ///
    /// - Parameter activityItems: The items to be shared
    /// - Returns: Always returns `true` as this activity can handle any items.
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return true
    }

    /// Prepares the activity with the items to be saved.
    ///
    /// This method is called before the activity is performed and stores the items
    /// for later use.
    ///
    /// - Parameter activityItems: The items to save to desktop
    override func prepare(withActivityItems activityItems: [Any]) {
        self.activityItems = activityItems
    }

    /// Performs the save to desktop action.
    ///
    /// Executes the action block with the prepared activity items and marks the
    /// activity as finished.
    override func perform() {
        actionBlock?(activityItems)
        activityDidFinish(true)
    }
}
