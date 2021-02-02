//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 2/2/21.
//

#if !os(macOS)
import UIKit

internal protocol InterfacePreviewsViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class InterfacePreviewsViewModel: NSObject {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: InterfacePreviewsViewModelProtocol?

    /// Single row representing a view that conforms to `ScytherPreviewable`
    func previewableRow(view: ScytherPreviewable.Type) -> PreviewableRow {
        var row: PreviewableRow = PreviewableRow()
        row.text = view.name
        row.detailText = view.details
        row.previewView = view.previewView

        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Preview Views Section
        var section: Section = Section()
        section.title = nil
        guard let classes = classesConformingToProtocol(ScytherPreviewable.self) as? [ScytherPreviewable.Type] else {
            delegate?.viewModelShouldReloadData()
            return
        }
        classes.forEach { (previewable) in
            section.rows.append(previewableRow(view: previewable))
        }

        //Setup Data
        sections.append(section)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension InterfacePreviewsViewModel {
    var title: String {
        return "UI Previews"
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
extension InterfacePreviewsViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}
#endif
