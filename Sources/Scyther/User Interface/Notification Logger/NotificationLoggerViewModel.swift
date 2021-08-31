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
    func viewModel(viewModel: NotificationLoggerViewModel?, shouldShowViewController viewController: UIViewController?)
}

internal class NotificationLoggerViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: NotificationLoggerViewModelProtocol?

    /// Single row representing a single value and key
    func defaultRow(name: String, value: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value

        return row
    }
    
    func additionalDataRow(notification: PushNotification) -> ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "View User-Additional Data"
        row.accessoryType = .disclosureIndicator
        row.actionBlock = { [weak self] in
            let viewController: TextReaderViewController = TextReaderViewController()
            viewController.title = "Additional Push Data"
            viewController.text = notification.additionalData.jsonString
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
        }

        return row
    }
    
    func rawPayloadRow(notification: PushNotification) -> ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "View Raw Payload"
        row.actionBlock = { [weak self] in
            let viewController: TextReaderViewController = TextReaderViewController()
            viewController.title = "Raw Push Payload"
            viewController.text = notification.rawPayload.jsonString
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
        }

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

        //Setup Notification Sections
        for notification: PushNotification in NotificationTester.instance.notifications.sorted(by: { $0.receivedAt ?? Date() > $1.receivedAt ?? Date() }) {
            var section: Section = Section()
            section.title = notification.receivedAt?.formatted(format: "dd MMM yyyy h:mm:ss a")
            section.rows.append(defaultRow(name: "Title", value: notification.aps.alert.title))
            section.rows.append(defaultRow(name: "Subtitle", value: notification.aps.alert.subtitle))
            section.rows.append(defaultRow(name: "Body", value: notification.aps.alert.body))
            if let badge: Int = notification.aps.badge {
                section.rows.append(defaultRow(name: "Badge", value: "\(badge)"))
            }
            if let category: String = notification.aps.category {
                section.rows.append(defaultRow(name: "Category", value: "\(category)"))
            }
            if let contentAvailable: Int = notification.aps.contentAvailable {
                section.rows.append(defaultRow(name: "Content-Available", value: "\(contentAvailable)"))
            }
            if let sound: String = notification.aps.sound {
                section.rows.append(defaultRow(name: "Sound", value: "\(sound)"))
            }
            section.rows.append(additionalDataRow(notification: notification))
            section.rows.append(rawPayloadRow(notification: notification))
            sections.append(section)
        }
        
        //Setup Empty Section
        var emptySection: Section = Section()
        emptySection.rows.append(emptyRow(text: "No notifications received"))
        if sections.isEmpty {
            sections.append(emptySection)
        }

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
