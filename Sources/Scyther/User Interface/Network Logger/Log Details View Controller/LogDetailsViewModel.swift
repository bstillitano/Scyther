//
//  LogDetailsViewModel.swift
//  
//
//  Created by Brandon Stillitano on 27/12/20.
//

#if !os(macOS)
import UIKit

internal protocol LogDetailsViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
    func viewModel(viewModel: LogDetailsViewModel?, shouldShowViewController viewController: UIViewController?)
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
    
    /// Single row with an action block for viewing the entire request URL
    func urlRow(url: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = "URL"
        row.detailText = url
        row.accessoryType = .disclosureIndicator
        row.actionBlock = { [weak self] in
            let viewController: TextReaderViewController = TextReaderViewController()
            viewController.title = "Request URL"
            viewController.text = url
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
        }

        return row
    }

    /// Single row representing a single value and key
    func defaultRow(name: String, value: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value

        return row
    }
    
    /// Button item for generating the cURL request corresponding to the `httpModel`
    var cURLRow: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "Export cURL request"
        row.actionBlock = { [weak self] in
            let viewController = UIActivityViewController(activityItems: [self?.httpModel?.requestCurl ?? ""],
                                                      applicationActivities: nil)
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
            
        }

        return row
    }
    
    /// Button item for opening a view controller that contains a UILabel with the request body set
    var viewRequestButtonRow: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "View request body"
        row.actionBlock = { [weak self] in
            let viewController: TextReaderViewController = TextReaderViewController()
            viewController.title = "Request body"
            viewController.text = self?.httpModel?.getRequestBody() as String?
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
        }

        return row
    }
    
    /// Button item for opening a view controller that contains a UILabel with the response body set
    var viewResponseButtonRow: ButtonRow {
        var row: ButtonRow = ButtonRow()
        row.text = "View reponse body"
        row.actionBlock = { [weak self] in
            let viewController: TextReaderViewController = TextReaderViewController()
            viewController.title = "Response body"
            viewController.text = self?.httpModel?.getResponseBody() as String?
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
        /// Clear Data
        sections.removeAll()

        /// Setup Overview Section
        var overviewSection: Section = Section()
        overviewSection.title = "Overview"
        overviewSection.rows.append(urlRow(url: httpModel?.requestURL ?? ""))
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

        /// Setup Request Headers Section
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
        
        /// Setup Request Body Section
        var requestBodySection: Section = Section()
        requestBodySection.title = "Request Body"
        if String(httpModel?.getRequestBody() ?? "").isEmpty {
            requestBodySection.rows.append(emptyRow(text: "No content sent"))
        } else {
            requestBodySection.rows.append(viewRequestButtonRow)
        }
        
        /// Setup Response Headers Section
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
        
        /// Setup Response Body Section
        var responseBodySection: Section = Section()
        responseBodySection.title = "Response Body"
        if String(httpModel?.getResponseBody() ?? "").isEmpty {
            responseBodySection.rows.append(emptyRow(text: "No data received"))
        } else {
            responseBodySection.rows.append(viewResponseButtonRow)
        }
        
        /// Setup Developer Section
        var developerSection: Section = Section()
        developerSection.title = "Developer Info"
        developerSection.rows.append(defaultRow(name: "Request time",
                                                value: httpModel?.requestTime))
        developerSection.rows.append(defaultRow(name: "Response time",
                                                value: httpModel?.responseTime))
        developerSection.rows.append(defaultRow(name: "Cache Policy",
                                                value: httpModel?.requestCachePolicy))
        developerSection.rows.append(defaultRow(name: "Timeout",
                                                value: httpModel?.requestTimeout))
        developerSection.rows.append(cURLRow)
        
        /// Setup Data
        sections.append(overviewSection)
        sections.append(requestHeadersSection)
        sections.append(requestBodySection)
        sections.append(responseHeadersSection)
        sections.append(responseBodySection)
        sections.append(developerSection)
        
        /// Call Delegate
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
