//
//  SubtitleRow.swift
//  Scyther
//
//  Created by Brandon Stillitano on 15/12/20.
//

import UIKit

class SubtitleRow: Row {
    public init() {}
    
    var style: RowStyle = .subtitle
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var accessoryView: UIView?
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType?
}
