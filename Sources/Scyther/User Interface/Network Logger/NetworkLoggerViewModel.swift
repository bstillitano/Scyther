//
//  NetworkLoggerViewModel.swift
//  
//
//  Created by Brandon Stillitano on 24/12/20.
//

#if !os(macOS)
import UIKit

internal protocol NetworkLoggerViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class NetworkLoggerViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: NetworkLoggerViewModelProtocol?

    /// Single row representing a network request
    func networkRow(httpModel: LoggerHTTPModel) -> NetworkLogRow {
        let row: NetworkLogRow = NetworkLogRow()
        row.httpMethod = httpModel.requestMethod
        row.httpStatusCode = httpModel.responseStatus
        row.httpRequestTime = httpModel.requestTime
        row.httpStatusColor = httpStatusColor(for: httpModel.responseStatus ?? 0)
        row.httpRequestURL = httpModel.requestURL
        row.accessoryType = .disclosureIndicator
        return row
    }
    
    /// Returns a `UIColor` representing the response code from the remote. Uses https://developer.mozilla.org/en-US/docs/Web/HTTP/Status as a reference.
    private func httpStatusColor(for responseCode: Int) -> UIColor {
        switch responseCode {
        case ..<1:
            return .systemGray
        case ..<100:
            return .systemBlue
        case ..<200:
            return .systemOrange
        case ..<300:
            return.systemGreen
        case ..<400:
            return .systemPurple
        case ..<600:
            return .systemRed
        default:
            return .systemGray
        }
    }

    @objc func prepareObjects() {
        /// Clear Data
        sections.removeAll()

        /// Setup Logs Section
        var logsSection: Section = Section()
        logsSection.title = nil
        for log in LoggerHTTPModelManager.sharedInstance.getModels() {
            logsSection.rows.append(networkRow(httpModel: log))
        }

        /// Setup Data
        sections.append(logsSection)

        /// Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension NetworkLoggerViewModel {
    var title: String {
        return "Network Logger"
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
extension NetworkLoggerViewModel {
    private func section(for index: Int) -> Section? {
        guard sections.indices.contains(index) else {
            return nil
        }
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else {
            return nil
        }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
