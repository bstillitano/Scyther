//
//  UITableViewStyle+Extensions.swift
//  
//
//  Created by Brandon Stillitano on 22/12/20.
//

import UIKit

extension UITableView.Style {
    internal static var insetGroupedSafe: UITableView.Style {
        if #available(iOS 13.0, *) {
            return .insetGrouped
        } else {
            return .grouped
        }
    }
}
