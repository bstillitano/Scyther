//
//  NotitifcationTester.swift
//
//
//  Created by Brandon Stillitano on 15/2/21.
//

#if !os(macOS)
import UIKit

internal protocol NotitificationTesterProtocol: class {
    func viewModelShouldReloadData()
}

internal class NotitifcationTesterViewModel {
    // MARK: - Data
    private var sections: [Section] = []
    
    // MARK: - Notification Params
    private var playSound: Bool = true
    private var repeatNotification: Bool = true
    private var increaseBadge: Bool = true

    // MARK: - Delegate
    weak var delegate: NotitificationTesterProtocol?

    func valueRow(title: String?, text: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.detailText = text
        row.text = title
        row.style = .default
        row.accessoryType = UITableViewCell.AccessoryType.none
        return row
    }
    
    /// Switch representing whether the notification that is sent should play a sound or not
    var playSoundSwitch: SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Play sound"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = playSound
        switchView.actionBlock = { [weak self] in
            self?.playSound = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

        return row
    }
    
    /// Switch representing whether the notification that is sent should be repeated
    var repeatSwitch: SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Repeat"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = playSound
        switchView.actionBlock = { [weak self] in
            self?.repeatNotification = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

        return row
    }
    
    /// Switch representing whether the notification that is sent should increment the app badge or not
    var incrementBadgeSwitch: SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Increment app badge"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = playSound
        switchView.actionBlock = { [weak self] in
            self?.increaseBadge = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

        return row
    }

    /// Button item that allows the caller to clear the notitifcation badge on the running app
    var clearBadge: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Clear app badge"
        row.actionBlock = {
            UIApplication.shared.applicationIconBadgeNumber = 0
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
        return row
    }

    /// Button item that allows the caller to increment the notitifcation badge on the running app
    var incrementBadge: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Increment app badge"
        row.actionBlock = {
            let badgeCount = UIApplication.shared.applicationIconBadgeNumber
            UIApplication.shared.applicationIconBadgeNumber = badgeCount + 1
        }
        return row
    }

    /// Button item that allows the caller to decrease the notitifcation badge on the running app
    var decreaseBadge: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Decrease app badge"
        row.actionBlock = {
            let badgeCount = UIApplication.shared.applicationIconBadgeNumber
            UIApplication.shared.applicationIconBadgeNumber = badgeCount - 1
        }
        return row
    }

    /// Button item that allows the caller to schedule a given dummy push notification
    var sendNotifcation: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Send push notification"
        row.actionBlock = { [weak self] in
            NotificationTester.instance.scheduleNotification(withTitle: "",
                                                             withBody: "",
                                                             withSound: self?.playSound ?? true,
                                                             withDelay: 2,
                                                             withRepeat: self?.repeatNotification ?? false,
                                                             andIncreaseBadge: self?.increaseBadge ?? true)
        }
        return row
    }

    /// Button item that allows the caller to cancel all scheduled notifications
    var cancelPending: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Cancel scheduled notifications"
        row.actionBlock = {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Send Section
        var sendSection: Section = Section()
        sendSection.title = "Send a test"
        sendSection.rows.append(playSoundSwitch)
        sendSection.rows.append(repeatSwitch)
        sendSection.rows.append(incrementBadgeSwitch)
        sendSection.rows.append(sendNotifcation)

        //Setup Badge Section
        var badgeSection: Section = Section()
        badgeSection.title = "App badge"
        badgeSection.rows.append(incrementBadge)
        badgeSection.rows.append(decreaseBadge)
        badgeSection.rows.append(clearBadge)
        badgeSection.rows.append(cancelPending)

        //Setup Data
        sections.append(sendSection)
        sections.append(badgeSection)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension NotitifcationTesterViewModel {
    var title: String {
        return "Notification Tester"
    }

    var numberOfSections: Int {
        return sections.count
    }

    func title(forSection index: Int) -> String? {
        return sections[index].title
    }

    func numbeOfRows(inSection index: Int) -> Int {
        return rows(inSection: index)?.count ?? 0
    }

    internal func row(at indexPath: IndexPath) -> Row? {
        guard let rows = rows(inSection: indexPath.section) else { return nil }
        guard rows.indices.contains(indexPath.row) else { return nil }
        return rows[indexPath.row]
    }

    func title(for row: Row, indexPath: IndexPath) -> String? {
        return row.text
    }

    func performAction(for row: Row, indexPath: IndexPath) {
        row.actionBlock?()
    }
}

// MARK: - Private data accessors
extension NotitifcationTesterViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}

extension NotitifcationTesterViewModel {
    @objc
    func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
}
#endif
