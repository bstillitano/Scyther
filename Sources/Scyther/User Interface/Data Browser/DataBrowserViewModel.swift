//
//  File.swift
//
//
//  Created by Brandon Stillitano on 19/9/21.
//

#if !os(macOS)
import UIKit

internal protocol DataBrowserViewModelProtocol: AnyObject {
    func viewModelShouldReloadData()
    func viewModel(viewModel: DataBrowserViewModel?, shouldShowViewController viewController: UIViewController?)
}

internal class DataBrowserViewModel {
    // MARK: - Data
    private var sections: [Section] = []
    internal var data: [String: AnyObject] = [:] {
        didSet {
            prepareObjects()
        }
    }

    // MARK: - Delegate
    weak var delegate: DataBrowserViewModelProtocol?

    /// Single row representing a single value and key
    func defaultRow(name: String?, value: String?, actionBlock: ActionBlock? = nil) -> DefaultRow {
        let row: DefaultRow = DefaultRow()
        row.text = name
        row.detailText = value
        row.actionBlock = actionBlock
        row.accessoryType = actionBlock == nil ? .none : .disclosureIndicator
        return row
    }
    
    /// Single row representing a single value and key
    func subtitleRow(name: String?, value: String?, actionBlock: ActionBlock? = nil) -> SubtitleRow {
        let row: SubtitleRow = SubtitleRow()
        row.text = name
        row.detailText = value
        row.actionBlock = actionBlock
        row.accessoryType = actionBlock == nil ? .none : .disclosureIndicator
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
        
        let mockData: [String : Any] = [
            "String" : "String",
            "Int": 1,
            "Bool": true,
            "Dictionary": [
                "String" : "String",
                "Int": 1,
                "Bool": true
            ]
        ]

        //Setup Sections
        var section: Section = Section()
        section.title = "Data"
        for value in mockData {
            let dataRow = DataRow(title: value.key, from: value.value)
            section.rows.append(objectFor(dataRow))
        }
        
        //Setup Sections
        sections.append(section)
        
        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }

    private func objectFor(_ dataRow: DataRow) -> Row {
        switch dataRow {
        case .string(let title, let data):
            if data?.count ?? 0) > 20
                return defaultRow(name: title, value: data)
            } else {
                return subtitleRow(name: title, value: data)
            }

        case .json(let title, _):
            break

        case .array(let title, _):
            break

        case .dictionary(let title, _):
            break
        }
        return defaultRow(name: "asd", value: "asd")
    }
}

// MARK: - Public data accessors
extension DataBrowserViewModel {
    var title: String {
        return "Data Browser"
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
extension DataBrowserViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif

