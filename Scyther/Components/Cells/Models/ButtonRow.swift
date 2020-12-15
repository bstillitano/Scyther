//
//  ButtonRow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import UIKit

internal struct ButtonRow: Row {
    public init() {}
    
    var style: RowStyle = .button
    var detailActionViewController: UIViewController?
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var switchView: UIActionSwitch = UIActionSwitch()
    var accessoryView: UIView?
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType?
}
