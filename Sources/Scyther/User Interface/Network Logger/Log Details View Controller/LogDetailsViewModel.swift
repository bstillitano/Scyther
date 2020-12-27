//
//  LogDetailsViewModel.swift
//  
//
//  Created by Brandon Stillitano on 27/12/20.
//

#if !os(macOS)
import UIKit

internal protocol LogDetailsViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class LogDetailsViewModel {
    // MARK: - Data
    private var sections: [Section] = []
    internal var httpModel: LoggerHTTPModel? = nil {
        didSet {
            prepareObjects()
        }
    }
    // MARK: - Delegate
    weak var delegate: LogDetailsViewModelProtocol?

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
        //Clear Data
        sections.removeAll()

        //Setup Overview Section
        var overviewSection: Section = Section()
        overviewSection.title = "Overview"
        overviewSection.rows.append(defaultRow(name: "URL",
                                               value: httpModel?.requestURL))
        overviewSection.rows.append(defaultRow(name: "Method",
                                               value: httpModel?.requestMethod))
        overviewSection.rows.append(defaultRow(name: "Response Code",
                                               value: "\(httpModel?.responseStatus ?? 0)"))
        overviewSection.rows.append(defaultRow(name: "Response Size",
                                               value: "\(httpModel?.responseBodyLength ?? 0) bytes"))
        overviewSection.rows.append(defaultRow(name: "Date",
                                               value: httpModel?.requestDate?.formatted()))
        overviewSection.rows.append(defaultRow(name: "Duration",
                                               value: String(format: "%.2fs", httpModel?.requestDuration ?? 0)))

        //Setup Request Headers Section
        var requestHeadersSection: Section = Section()
        requestHeadersSection.title = "Request Headers"
        if httpModel?.requestHeaders?.isEmpty ?? true {
            requestHeadersSection.rows.append(emptyRow(text: "No headers sent"))
        } else {
            for header in httpModel?.requestHeaders ?? [:] {
                requestHeadersSection.rows.append(defaultRow(name: header.key as? String ?? "",
                                                             value: header.value as? String))
            }
        }
        
        //Setup Response Headers Section
        var responseHeadersSection: Section = Section()
        responseHeadersSection.title = "Response Headers"
        if httpModel?.responseHeaders?.isEmpty ?? true {
            responseHeadersSection.rows.append(emptyRow(text: "No headers received"))
        } else {
            for header in httpModel?.responseHeaders ?? [:] {
                responseHeadersSection.rows.append(defaultRow(name: header.key as? String ?? "",
                                                              value: header.value as? String))
            }
        }
        
        //Setup Data
        sections.append(overviewSection)
        sections.append(requestHeadersSection)
        // TODO - Request Body
        sections.append(responseHeadersSection)
        
        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension LogDetailsViewModel {
    var title: String {
        return "Request Details"
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
extension LogDetailsViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
