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

    // MARK: - Delegate
    weak var delegate: NotitificationTesterProtocol?

    func valueRow(font: UIFont?) -> FontRow {
        let row: FontRow = FontRow()
        row.text = font?.fontName
        row.font = font
        row.style = .font
        row.accessoryType = UITableViewCell.AccessoryType.none
        return row
    }
    
    /// Button item that allows the caller to clear the notitifcation badge on the running app
    var clearBadge: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Clear app badge"
        row.actionBlock = {
            UIApplication.shared.applicationIconBadgeNumber = 0
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
        row.actionBlock = {[weak self] in
            NotificationTester.instance.scheduleNotification()
        }
        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Send Section
        var sendSection: Section = Section()
        sendSection.title = "Send"
        sendSection.rows.append(sendNotifcation)
        
        //Setup Badge Section
        var badgeSection: Section = Section()
        badgeSection.title = "App badge"
        badgeSection.rows.append(incrementBadge)
        badgeSection.rows.append(decreaseBadge)
        badgeSection.rows.append(clearBadge)
        
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
#endif
