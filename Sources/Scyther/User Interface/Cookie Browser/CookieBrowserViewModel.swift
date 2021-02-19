//
//  CookieBrowserViewModel.swift
//  
//
//  Created by Brandon Stillitano on 20/2/21.
//

#if !os(macOS)
import UIKit

internal protocol CookieBrowserViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class CookieBrowserViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: CookieBrowserViewModelProtocol?
    
    /// Single row representing a single cookie
    func defaultRow(name: String, value: String?) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = String(value ?? "NaS")

        return row
    }

    /// Button item that allows the caller to restore all `Toggle` values to their remote value
    var restoreDefaults: ButtonRow {
        //Setup Row
        var row: ButtonRow = ButtonRow()
        row.text = "Restore remote values"
        row.actionBlock = {[weak self] in
            for toggle: Toggle in Toggler.instance.toggles {
                Toggler.instance.setLocalValue(value: toggle.remoteValue, forToggleWithName: toggle.name)
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
        var coookiesSection: Section = Section()
        coookiesSection.title = "WKWebView Cookies"
        for cookie: HTTPCookie in CookieBrowser.instance.cookies {
            coookiesSection.rows.append(defaultRow(name: cookie.name,
                                                   value: cookie.domain))
        }
        if coookiesSection.rows.isEmpty {
            coookiesSection.rows.append(emptyRow(text: "No HTTP Cookies"))
        }
        
        //Setup Data
        sections.append(coookiesSection)

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
extension CookieBrowserViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}


extension CookieBrowserViewModel {
    @objc
    func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
}
#endif
