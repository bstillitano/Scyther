//
//  Row.swift
//  Scyther
//
//  Created by Brandon Stillitano on 10/12/20.
//

import UIKit

/// Enum which defines all the possible different row styles.
enum RowStyle: String {
    case `default`
    case subtitle
    case deviceHeader
    case action
}

internal struct Row {
    internal var title: String?
    internal var detailText: String?
    internal var iconURL: URL?
    internal var image: UIImage?
    internal var style: RowStyle = .default
    internal var detailActionViewController: UIViewController?
    internal var actionBlock: ActionBlock?
    internal var isHidden: Bool = false
}
