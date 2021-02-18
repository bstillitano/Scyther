//
//  GridOverlayViewModel.swift
//  
//
//  Created by Brandon Stillitano on 18/2/21.
//

#if !os(macOS)
import UIKit

internal protocol GridOverlayViewModelProtocol: class {
    func viewModelShouldReloadData()
}

internal class GridOverlayViewModel {
    // MARK: - Data
    private var sections: [Section] = []

    // MARK: - Delegate
    weak var delegate: GridOverlayViewModelProtocol?

    /// Global overrides switch object. Controls whether overrides are respected or not.
    var enableGrid: SwitchAccessoryRow {
        //Setup Row
        var row: SwitchAccessoryRow = SwitchAccessoryRow()
        row.text = "Enable grid"

        //Setup Accessory
        let switchView = UIActionSwitch()
        switchView.isOn = GridOverlay.instance.enabled
        switchView.actionBlock = {
            GridOverlay.instance.enabled = switchView.isOn
        }
        switchView.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        row.accessoryView = switchView

        return row
    }
    
    var sizeSlider: SliderRow {
        //Setup Slider
        let slider: UISlider = UISlider()
        slider.minimumValue = 1
        slider.maximumValue = 100
        slider.value = Float(GridOverlay.instance.size)
        slider.addTarget(self, action: #selector(sizeSliderChanged(_:)), for: .valueChanged)
        
        //Setup Row
        let row: SliderRow = SliderRow()
        row.text = "Grid size"
        row.slider = slider
        return row
    }

    func prepareObjects() {
        //Clear Data
        sections.removeAll()

        //Setup Overlay Section
        var overlaySection: Section = Section()
        overlaySection.title = nil
        overlaySection.rows = [enableGrid]
        
        //Setup Options Section
        var optionsSection: Section = Section()
        optionsSection.title = "Grid Options"
        optionsSection.rows = [sizeSlider]

        //Setup Data
        sections.append(overlaySection)
        sections.append(optionsSection)

        //Call Delegate
        delegate?.viewModelShouldReloadData()
    }
}

// MARK: - Public data accessors
extension GridOverlayViewModel {
    var title: String {
        return "Grid Overlay"
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
extension GridOverlayViewModel {
    private func section(for index: Int) -> Section? {
        return sections[index]
    }

    private func rows(inSection index: Int) -> [Row]? {
        guard let section = section(for: index) else { return nil }
        return section.rows.filter { !$0.isHidden }
    }
}


extension GridOverlayViewModel {
    @objc
    func switchToggled(_ sender: UIActionSwitch?) {
        sender?.actionBlock?()
    }
    
    @objc
    func sizeSliderChanged(_ sender: UISlider?) {
        guard let slider: UISlider = sender else {
            return
        }
        GridOverlay.instance.size = Int(slider.value)
        prepareObjects()
    }
}
#endif
