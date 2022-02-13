//
//  File.swift
//
//
//  Created by Brandon Stillitano on 12/2/22.
//

import UIKit

/// Internal class used to allow saving files to the Desktop when running on a MacOS Simulator
internal class SaveToDesktopActivity: UIActivity {
    // MARK: - Data
    var activityItems: [Any] = []
    private var title: String?
    private var actionBlock: ActionBlockWithData<[Any]>?

    // MARK: - Lifecycle
    deinit {
        title = nil
        actionBlock = nil
    }

    init(title: String, actionBlock: ActionBlockWithData<[Any]>?) {
        self.title = title
        self.actionBlock = actionBlock
        super.init()
    }

    // MARK: - Overrides
    override var activityTitle: String? {
        return title
    }

    override var activityImage: UIImage? {
        return UIImage(systemName: "desktopcomputer.and.arrow.down")
    }

    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType(rawValue: "io.stillitano.ScytherInternal.saveToDesktopActivity")
    }

    override class var activityCategory: UIActivity.Category {
        return .action
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return true
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        self.activityItems = activityItems
    }

    override func perform() {
        actionBlock?(activityItems)
        activityDidFinish(true)
    }
}
