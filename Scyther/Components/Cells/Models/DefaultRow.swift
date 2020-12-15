//
//  DefaultRow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 13/12/20.
//

import UIKit

class DefaultRow: Row {
    public init() {}
    
    var style: RowStyle = .default
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var accessoryView: UIView?
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType?
}
