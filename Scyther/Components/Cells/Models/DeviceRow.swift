//
//  DeviceRow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 16/12/20.
//

import UIKit

class DeviceRow: Row {
    public init() {}
    
    var style: RowStyle = .deviceHeader
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var accessoryView: UIView?
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType?
}
