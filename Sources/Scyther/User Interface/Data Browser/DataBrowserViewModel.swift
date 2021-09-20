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
    internal var data: [String: [String: Any]] = [:] {
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

        //Setup Sections
        for value in data {
            var section: Section = Section()
            section.title = value.key
            let dataRows: [Row] = value.value.map { object in
                let dataRow: DataRow = DataRow(title: object.key, from: object.value)
                return objectFor(dataRow)
            }
            section.rows.append(contentsOf: dataRows)
            if section.rows.isEmpty {
                section.rows.append(emptyRow(text: "No \(value.key)"))
            }
            sections.append(section)
        }

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }

    private func objectFor(_ dataRow: DataRow) -> Row {
        switch dataRow {
        case .array(let title, let arrayData):
            var organisedData: [String: [String: Any]] = [:]
            var subData: [String: Any] = [:]
            arrayData.enumerated().forEach({ (index, element) in
                subData["\(index)"] = element
            })
            organisedData["Array Data"] = subData
            return defaultRow(name: title, value: "Array") { [weak self] in
                let viewController: DataBrowserViewController = DataBrowserViewController(data: organisedData)
                self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
            }

        case .dictionary(let title, let dictionaryData):
            let organisedData: [String: [String: Any]] = [
                "Dictionary Data": dictionaryData
            ]
            return defaultRow(name: title, value: "Dictionary") { [weak self] in
                let viewController: DataBrowserViewController = DataBrowserViewController(data: organisedData)
                self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
            }

        case .json(let title, let jsonData):
            if let arrayData = jsonData as? NSArray {
                var organisedData: [String: [String: Any]] = [:]
                var subData: [String: Any] = [:]
                arrayData.enumerated().forEach({ (index, element) in
                    subData["\(index)"] = element
                })
                organisedData["Array Data"] = subData
                return defaultRow(name: title, value: "Array") { [weak self] in
                    let viewController: DataBrowserViewController = DataBrowserViewController(data: organisedData)
                    self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
                }
            } else if let dictionaryData = jsonData as? NSDictionary {
                let organisedData: [String: [String: Any]] = [
                    "Dictionary Data": dictionaryData.swiftDictionary
                ]
                return defaultRow(name: title, value: "Dictionary") { [weak self] in
                    let viewController: DataBrowserViewController = DataBrowserViewController(data: organisedData)
                    self?.delegate?.viewModel(viewModel: self, shouldShowViewController: viewController)
                }
            } else {
                return subtitleRow(name: title, value: String(describing: jsonData))
            }

        case .string(let title, let stringData):
            return defaultRow(name: title, value: stringData)
        }
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
