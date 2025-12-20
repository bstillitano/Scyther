//
//  CookieBrowserViewModel.swift
//  
//
//  Created by Brandon Stillitano on 20/2/21.
//

#if !os(macOS)
import UIKit

internal protocol CookieBrowserViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
    func viewModel(viewModel: CookieBrowserViewModel?, shouldShowViewController viewController: UIViewController?)
}

internal class CookieBrowserViewModel {
    // MARK: - Data
    private var sections: [TableSection] = []

    // MARK: - Delegate
    weak var delegate: CookieBrowserViewModelProtocol?
    
    /// Single row representing a single cookie
    func subtitleRow(cookie: HTTPCookie) -> SubtitleRow {
        let row: SubtitleRow = SubtitleRow()
        row.text = cookie.name
        row.detailText = cookie.domain
        row.accessoryType = .disclosureIndicator
        row.actionBlock = { [weak self] in
            let viewController: CookieDetailsViewController = CookieDetailsViewController(cookie: cookie)
            self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
        }

        return row
    }

    /// Button item that allows the caller to clear all cookies from HTTPCookieStorage
    var clearAllCookies: ButtonRow {
        //Setup Row
        var row: ButtonRow = ButtonRow()
        row.text = "Clear all cookies"
        row.actionBlock = {[weak self] in
            for cookie: HTTPCookie in CookieBrowser.instance.cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
            self?.prepareObjects()
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

        //Setup Cookies Section
        var coookiesSection: TableSection = TableSection()
        coookiesSection.title = "HTTPCookieStorage Cookies"
        for cookie: HTTPCookie in CookieBrowser.instance.cookies {
            coookiesSection.rows.append(subtitleRow(cookie: cookie))
        }
        if coookiesSection.rows.isEmpty {
            coookiesSection.rows.append(emptyRow(text: "No HTTP Cookies"))
        }
        
        //Setup Clear Section
        var clearSection: TableSection = TableSection()
        clearSection.rows.append(clearAllCookies)
        
        //Setup Data
        sections.append(coookiesSection)
        if !(coookiesSection.rows.first is EmptyRow) {
            sections.append(clearSection)
        }

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension CookieBrowserViewModel {
    var title: String {
        return "Cookie Browser"
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
    
    func canEditRow(at indexPath: IndexPath) -> Bool {
        return true
    }
}

// MARK: - Private data accessors
extension CookieBrowserViewModel {
    private func section(for index: Int) -> TableSection? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
