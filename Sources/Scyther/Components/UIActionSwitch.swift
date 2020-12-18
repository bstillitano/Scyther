//
//  UIActionSwitch.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

#if !os(macOS)
import UIKit

class UIActionSwitch: UISwitch {
    var actionBlock: ActionBlock?
}
#endif
