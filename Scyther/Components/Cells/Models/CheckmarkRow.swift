//
//  CheckmarkRow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import UIKit

internal struct CheckmarkRow: Row {
    public init() {}
    
    var style: RowStyle = .checkmarkAccessory
    var detailActionViewController: UIViewController?
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var switchView: UIActionSwitch = UIActionSwitch()
    var accessoryView: UIView?
    var checked: Bool = false
}
