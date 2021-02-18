//
//  SliderRow.swift
//  
//
//  Created by Brandon Stillitano on 19/2/21.
//

#if !os(macOS)
import UIKit

class SliderRow: Row {
    public init() {}
    
    var style: RowStyle = .slider
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var accessoryView: UIView?
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType?
}
#endif
