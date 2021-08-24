//
//  FontRow.swift
//  
//
//  Created by Brandon Stillitano on 15/2/21.
//

#if !os(macOS)
import UIKit

class FontRow: Row {
    public init() {}
    
    var style: RowStyle = .font
    var actionBlock: ActionBlock?
    var isHidden: Bool = false
    var text: String?
    var detailText: String?
    var accessoryView: UIView?
    var image: UIImage?
    var imageURL: URL?
    var accessoryType: UITableViewCell.AccessoryType?
    var font: UIFont?
    var shouldShowMenuForRow: Bool? = false
}
#endif
