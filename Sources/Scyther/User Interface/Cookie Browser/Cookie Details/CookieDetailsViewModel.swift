//
//  CookieDetailsViewModel.swift
//  
//
//  Created by Brandon Stillitano on 20/2/21.
//

#if !os(macOS)
import UIKit

internal protocol CookieDetailsViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class CookieDetailsViewModel {
    // MARK: - Data
    private var sections: [Section] = []
    internal var cookie: HTTPCookie? = nil {
        didSet {
            prepareObjects()
        }
    }

    // MARK: - Delegate
    weak var delegate: CookieDetailsViewModelProtocol?
    
    /// Single row with an action block for viewing the entire request URL
    func cookieRow(key: String?, value: String?) -> SubtitleRow {
        let row: SubtitleRow = SubtitleRow()
        row.text = key
        row.detailText = value?.isEmpty ?? true ? "-" : value ?? "-"
        return row
    }

    /// Single row representing a single value and key
    func defaultRow(name: String, value: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value

        return row
    }

    /// Empty row that contains text in a 'disabled' style
    func emptyRow(text: String) -> EmptyRow {
        var row: EmptyRow = EmptyRow()
        row.text = text

        return row
    }

    func prepareObjects() {
        /// Clear Data
        sections.removeAll()

        /// Setup Key/Values Section
        var keyValuesSection: Section = Section()
        keyValuesSection.title = "Key/Values"
        keyValuesSection.rows.append(cookieRow(key: "Name",
                                               value: cookie?.name))
        keyValuesSection.rows.append(cookieRow(key: "Value",
                                               value: cookie?.value))
        keyValuesSection.rows.append(cookieRow(key: "Path",
                                               value: cookie?.path))
        keyValuesSection.rows.append(cookieRow(key: "Domain",
                                               value: cookie?.domain))
        keyValuesSection.rows.append(cookieRow(key: "Comment",
                                               value: cookie?.comment))
        keyValuesSection.rows.append(cookieRow(key: "Comment URL",
                                               value: cookie?.commentURL?.absoluteString))
        keyValuesSection.rows.append(cookieRow(key: "Expires",
                                               value: cookie?.expiresDate?.formatted()))
        keyValuesSection.rows.append(cookieRow(key: "Expires",
                                               value: cookie?.expiresDate?.formatted()))
        keyValuesSection.rows.append(cookieRow(key: "HTTP Only",
                                               value: cookie?.isHTTPOnly.stringValue))
        keyValuesSection.rows.append(cookieRow(key: "HTTPS Only",
                                               value: cookie?.isSecure.stringValue))
        keyValuesSection.rows.append(cookieRow(key: "Session Only",
                                               value: cookie?.isSessionOnly.stringValue))
        keyValuesSection.rows.append(cookieRow(key: "Ports",
                                               value: cookie?.portList?.compactMap( { "\($0)" }).joined(separator: ", ")))
        keyValuesSection.rows.append(cookieRow(key: "Version",
                                               value: "\(cookie?.version ?? 0)"))
        
        
        /// Setup Properties Section
        var propertiesSection: Section = Section()
        propertiesSection.title = "Properties"
        //TODO
        if propertiesSection.rows.isEmpty {
            propertiesSection.rows.append(emptyRow(text: "No cookie properties set"))
        }
        
        /// Setup Data
        sections.append(keyValuesSection)
        sections.append(propertiesSection)
        
        /// Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension CookieDetailsViewModel {
    var title: String {
        return "Cookie Details"
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
extension CookieDetailsViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
