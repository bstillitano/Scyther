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
    func viewModel(viewModel: NetworkLoggerViewModel?, shouldShowViewController viewController: UIViewController?)
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
        row.httpRequestTime = String(format: "%.2fs", httpModel.requestDuration ?? 0)
        row.httpStatusColor = httpStatusColor(for: httpModel.responseStatus ?? 0)
        row.httpRequestURL = httpModel.requestURL
        row.httpModel = httpModel
        row.accessoryType = .disclosureIndicator
        row.actionBlock = { [weak self] in
            let logDetailsViewController: LogDetailsViewController = LogDetailsViewController(httpModel: httpModel)
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: logDetailsViewController)
        }
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

    @objc func prepareObjects(filteredOn searchString: String? = nil) {
        /// Clear Data
        sections.removeAll()

        /// Setup Logs Section
        var logsSection: Section = Section()
        logsSection.title = nil
        
        /// Check for Filtered Data
        if searchString != nil && !(searchString?.isEmpty ?? true) {
            for log in LoggerHTTPModelManager.sharedInstance.getModels().filter( { ($0.requestURL?.lowercased().contains(searchString?.lowercased() ?? "") ?? false) || ($0.responseStatus ?? 0 == Int(searchString ?? "") ?? 0) } ) {
                logsSection.rows.append(networkRow(httpModel: log))
            }
        } else {
            for log in LoggerHTTPModelManager.sharedInstance.getModels() {
                logsSection.rows.append(networkRow(httpModel: log))
            }
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
