//
//  FeatureFlagsViewController.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import DTTableViewManager
import UIKit

protocol FeatureFlagsViewModelProtocol: class {
    func viewModelShouldRefreshView(viewModel: FeatureFlagsViewModel?)
}

class FeatureFlagsViewModel: NSObject {
    // MARK: Data
    var objects: [Any] = []

    // MARK: Delegate
    weak var delegate: FeatureFlagsViewModelProtocol?

    override public init() {
        super.init()

        /// Prepare Cell Objects
        prepareObjects()
    }

    private var masterOverrideHeader: SectionHeaderConfigObject {
        let value: SectionHeaderConfigObject = SectionHeaderConfigObject()
        value.text = "GLOBAL SETTINGS"
        value.customInsets = .globalMargin
        return value
    }

    private var masterOverrideSwitch: LabelSwitchConfigObject {
        let value: LabelSwitchConfigObject = LabelSwitchConfigObject()
        value.text = "Enable toggle overrides"
        value.switchIsOn = Toggler.instance.localOverridesEnabled
        value.actionBlock = {
            Toggler.instance.localOverridesEnabled = !Toggler.instance.localOverridesEnabled
        }
        value.customInsets = .top0Left2Bottom2Right2
        return value
    }

    private var togglesHeader: SectionHeaderConfigObject {
        let value: SectionHeaderConfigObject = SectionHeaderConfigObject()
        value.text = "FEATURE FLAGS"
        value.customInsets = .globalMargin
        return value
    }

    private func toggleSwitch(toggle: Toggle) -> LabelSwitchConfigObject {
        let value: LabelSwitchConfigObject = LabelSwitchConfigObject()
        value.text = toggle.name
        value.switchIsOn = toggle.localValue
        value.actionBlock = {
            Toggler.instance.setLocalValue(value: !Toggler.instance.value(forToggle: toggle.name),
                                           forToggleWithName: toggle.name)
        }
        value.customInsets = .top0Left2Bottom2Right2
        return value
    }

    private func prepareObjects() {
        //Clear Data
        objects.removeAll()

        //Setup Master Override
        objects.append(masterOverrideHeader)
        objects.append(masterOverrideSwitch)

        //Setup Flag Overrides
        objects.append(togglesHeader)
        for toggle: Toggle in Toggler.instance.toggles {
            objects.append(toggleSwitch(toggle: toggle))
        }
        //Check Data
//        guard order != nil else {
//            self.delegate?.viewModel(viewModel: self, shouldShowError: nil)
//            return
//        }
//
//        //Add Values
//        objects.append(supplierHeader)
//        objects.append(sorryLabel)
//        for reason in ReportReason.allCases {
//            objects.append(reasonCheckbox(reason: reason.rawValue))
//        }
//        objects.append(textField)
//        objects.append(submitButton)
//
        //Call Delegate
        self.delegate?.viewModelShouldRefreshView(viewModel: self)
    }
}
