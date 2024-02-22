//
//  PreviewableRow.swift
//  
//
//  Created by Brandon Stillitano on 2/2/21.
//

#if !os(macOS)
import UIKit

internal struct PreviewableRow: Row {
    public init() {}
    
    var style: RowStyle = .previewable
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
    var previewView: UIView = UIView()
    var shouldShowMenuForRow: Bool? = false
    var trailingSwipeActionsConfiguration: UISwipeActionsConfiguration?
}
#endif
