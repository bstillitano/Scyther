//
//  Row.swift
//  Scyther
//
//  Created by Brandon Stillitano on 11/12/20.
//

import UIKit

/// Enum which defines all the possible different row styles.
enum RowStyle: String {
    case `default`
    case subtitle
    case deviceHeader
    case button
    case switchAccessory
    case checkmarkAccessory
}

internal protocol Row {
    var text: String? {get set}
    var detailText: String? {get set}
    var accessoryView: UIView? {get set}
    var style: RowStyle {get set}
    var detailActionViewController: UIViewController? {get set}
    var actionBlock: ActionBlock? {get set}
    var isHidden: Bool {get set}
}

extension Row {
    internal var cellReuseIdentifier: String {
        return style.rawValue
    }
}
