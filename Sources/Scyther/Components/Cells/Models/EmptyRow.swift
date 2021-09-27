//
//  EmptyRow.swift
//  
//
//  Created by Brandon Stillitano on 27/12/20.
//

#if !os(macOS)
import UIKit

internal struct EmptyRow: Row {
    public init() {}
    
    var style: RowStyle = .emptyRow
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
    var shouldShowMenuForRow: Bool? = false
}
#endif
