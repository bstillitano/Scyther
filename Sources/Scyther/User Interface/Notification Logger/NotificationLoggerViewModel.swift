//
//  NotificationLoggerViewModel.swift
//  
//
//  Created by Brandon Stillitano on 31/8/21.
//

#if !os(macOS)
import UIKit

internal protocol NotificationLoggerViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
}

internal class NotificationLoggerViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: NotificationLoggerViewModelProtocol?

    /// Single checkable row value representing a single environment
    func notificationRow(notification: PushNotification) -> DefaultRow {
        var row: DefaultRow = DefaultRow()
        row.text = notification.receivedAt?.formatted()
        row.detailText = "Content-Avaialble: \(notification.aps.contentAvailable ?? -999)"
        return row
    }
    
    /// Empty row that contains text in a 'disabled' style
    func emptyRow(text: String) -> EmptyRow {
        var row: EmptyRow = EmptyRow()
        row.text = text

        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Notifications Section
        var notificationsSection: Section = Section()
        notificationsSection.title = "Notifications"
        notificationsSection.rows = NotificationTester.instance.notifications.sorted(by: { $0.receivedAt ?? Date() < $1.receivedAt ?? Date() }).map({ notificationRow(notification: $0) })
        if notificationsSection.rows.isEmpty {
            notificationsSection.rows.append(emptyRow(text: "No notifications received"))
        }

        //Setup Data
        sections.append(notificationsSection)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension NotificationLoggerViewModel {
    var title: String {
        return "Notification Logger"
    }

    var numberOfSections: Int {
        return sections.count
    }

    func title(forSection index: Int) -> String? {
        return sections[index].title
    }

    func numberOfRows(inSection index: Int) -> Int {
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
extension NotificationLoggerViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
