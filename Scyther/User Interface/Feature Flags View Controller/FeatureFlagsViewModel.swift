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
        value.text = "OVERRIDES ENABLED"
        value.customInsets = .globalMargin
        return value
    }

    private func prepareObjects() {
        //Clear Data
        objects.removeAll()

        //Setup Master Override
        objects.append(masterOverrideHeader)
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
