//
//  ValueTableViewCell.swift
//  DebugMenu
//
//  Created by Jack Perry on 1/1/20.
//  Copyright © 2020 Jack Perry. All rights reserved.
//

#if !os(macOS)
import UIKit
import Foundation

final internal class ValueTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)

        textLabel?.numberOfLines = 0
        textLabel?.adjustsFontSizeToFitWidth = true
        detailTextLabel?.adjustsFontSizeToFitWidth = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryType = .none
        textLabel?.text = nil
        detailTextLabel?.text = nil
        imageView?.image = nil
    }

}
#endif
