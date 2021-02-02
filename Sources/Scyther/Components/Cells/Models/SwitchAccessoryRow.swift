//
//  SwitchAccessoryRow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

#if !os(macOS)
import UIKit

internal struct SwitchAccessoryRow: Row {
    public init() {}
    
    var text: String?
    var detailText: String?
    var style: RowStyle = .switchAccessory
    var detailActionViewController: UIViewController?
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var accessoryView: UIView? = UIActionSwitch()
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType?
}
#endif
