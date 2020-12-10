//
//  SwitchAccessoryRow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

internal struct SwitchAccessoryRow {
    internal var cellReuseIdentifer: String = "switchAccessoryResuseIdentifier"
    internal var text: String?
    internal var detailText: String?
    internal var switchView: UISwitch = UISwitch()
    internal var actionBlock: ActionBlock?
    internal var isHidden: Bool = false
}
